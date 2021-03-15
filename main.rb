require 'sinatra'
require 'httparty'
require 'bcrypt'

require_relative 'db/lib'

if development?
  require 'sinatra/reloader'
  require 'pry'
end

enable :sessions

def logged_in?
  if session[:user_id]
    return true
  else
    return false
  end
end

def current_user
  results = run_sql("SELECT * FROM users WHERE id = $1;", [session[:user_id]])

  return results.first
end

get '/login' do

  erb :login
end

post '/sessions' do
  results = run_sql("SELECT * FROM users WHERE email = $1;", [params[:email]])

  if results.count == 1 && BCrypt::Password.new(results[0]['password_digest']).==(params[:password])
    session[:user_id] = results[0]['id']
    redirect '/'
  else
    erb :login
  end
end

delete '/sessions' do
  session[:user_id] = nil
  redirect '/login'
end


#################    users RESTful CRUD    #################
#################                          #################

get '/users/new' do
  erb :new_user
end

post '/users' do
  # insert user in the table

  password_digest = BCrypt::Password.create(params[:password])

  user_id = run_sql("INSERT INTO users (first_name, last_name, email, password_digest) VALUES ($1,$2,$3,$4) RETURNING id",[ params[:first_name], params[:last_name], params[:email], password_digest ])

  #set session id
  session[:user_id] = user_id[0]['id']

  # create a starting balance of $10000 in the trades table
  # record_trade(0, 0, 10000) 

  # set the session user_id to that of the user id just created
  redirect '/'
end

get '/users/:id' do
  result = run_sql("SELECT * FROM users WHERE id = $1",[params[:id]])
  user = result[0]

  erb :user_profile, locals: { user: user }
end

get '/users/:id/edit' do
  result = run_sql("SELECT * FROM users WHERE id = $1",[params[:id]])
  user = result[0]
  erb :edit_user, locals: { user: user}
end

patch '/users/:id' do

  run_sql(
    "UPDATE users SET first_name = $1, last_name = $2 WHERE id = $3;", 
    [ params[:first_name], params[:last_name], params[:id] ]
  )

  redirect "/users/#{params[:id]}"
end

delete '/users/:id' do
  redirect '/login' unless logged_in?

  run_sql("DELETE FROM users WHERE id = $1",[params[:id]])

  session[:user_id] = nil

  redirect '/'
end

############################################################


def get_btc_price
  result_string = HTTParty.get("https://api.coindesk.com/v1/bpi/currentprice.json")
  result = JSON.parse(result_string) # api sent back a string so need to convert to json
  price = result['bpi']['USD']['rate_float'].round(2)
  return price
end

def record_trade(price, no_of_coins, trade_size)
  run_sql("INSERT INTO trades (price, no_of_coins, trade_size, user_id) VALUES ($1, $2, $3, $4);", [price, no_of_coins, trade_size, session[:user_id]])
end

def get_cash_balance(user_id)
  cash_balance = 10000 # starting balance
  trades = run_sql("SELECT * FROM trades WHERE user_id = $1", [user_id])
  trades.each do |trade|
    cash_balance = cash_balance - trade['trade_size'].to_f
  end
  return cash_balance
end

def get_bitcoin_balance(user_id)
  bitcoin_balance = 0
  trades = run_sql("SELECT * FROM trades WHERE user_id = $1", [user_id])
  trades.each do |trade|
    bitcoin_balance = bitcoin_balance + trade['no_of_coins'].to_f
  end
  return bitcoin_balance.round(8)
end


def get_leaderboard
  gain_or_loss_values = [] # users and values are pushed
  matched_users = [] # into these 2 arrays at the same time so the indexes match.
  leaders = []
  #get a list of the users
  users = run_sql("SELECT * FROM users")
  users.each do |user|
    cash_balance = get_cash_balance(user['id'])
    bitcoin_balance = get_bitcoin_balance(user['id'])
    gain_or_loss_value = (cash_balance - 10000) + (bitcoin_balance * get_btc_price())

    gain_or_loss_values.push(gain_or_loss_value)
    matched_users.push(user)
  end

  while matched_users.length > 0 do
    index_of_max_val = gain_or_loss_values.each_with_index.max[1]
    gain_or_loss_value = gain_or_loss_values[index_of_max_val]
    matched_user = matched_users[index_of_max_val]
    leaders.push([matched_user, gain_or_loss_value])

    gain_or_loss_values.delete_at(index_of_max_val)
    matched_users.delete_at(index_of_max_val)
  end


  # portfolio_values = []
  # user_names = []
  # leaders = []
  # #get a list of the users
  # users = run_sql("SELECT * FROM users")
  # users.each do |user|
  #   cash_balance = get_cash_balance(user['id'])
  #   bitcoin_balance = get_bitcoin_balance(user['id'])
  #   portfolio_value = cash_balance + (bitcoin_balance * get_btc_price())

  #   portfolio_values.push(portfolio_value)
  #   user_names.push(user['first_name'])
  # end

  # 5.times do
  #   index_of_max_val = portfolio_values.each_with_index.max[1]
  #   max_val = portfolio_values[index_of_max_val]
  #   user_name = user_names[index_of_max_val]
  #   leaders.push([user_name, max_val])

  #   portfolio_values.delete_at(index_of_max_val)
  #   user_names.delete_at(index_of_max_val)
  # end

  return leaders
end

get '/' do
  # get the balances to display for the session user or zero balance if not logged in
  cash_balance = 0
  bitcoin_balance = 0

  if logged_in?
    cash_balance = get_cash_balance(session[:user_id])
    bitcoin_balance = get_bitcoin_balance(session[:user_id])
    # calculates balances each time. Would be a scaling issue. Will need to place the balances as a column in users table that updates after each trade, solving the need to traverse the whole trades table each time.
  end

  portfolio_value = cash_balance + (bitcoin_balance * get_btc_price())

  leaders = get_leaderboard()

  chat_box_messages = get_messages()

  erb :index, locals: { cash_balance: cash_balance, bitcoin_balance: bitcoin_balance, portfolio_value: portfolio_value, leaders: leaders, messages: chat_box_messages }
end


post '/trade' do
  redirect '/login' unless logged_in? # send to login if not logged in.
  
  price = get_btc_price()
  trade_cost = 0

  # convert the trade_cost to -ve if it's not a purchase & check for overdraw
  if params[:purchase]
    trade_cost = params[:trade_amount].to_f.round(2)
    if get_cash_balance(session[:user_id]) < trade_cost
      # trade can't exceed cash balance
      redirect '/'
    end
  else
    trade_cost = -(params[:trade_amount].to_f.round(2))   
    if -(trade_cost / price) > get_bitcoin_balance(session[:user_id])
      # if number of bitcoins required for the trade is > bitcoin balance
      redirect '/'
    end
  end

  no_of_bitcoins = (trade_cost / price).round(8)
  record_trade(price, no_of_bitcoins, trade_cost)
  
  redirect '/'
end


get '/trade_history/:id' do
  redirect '/login' unless logged_in? # send to login if not logged in.

  history = run_sql("SELECT * FROM trades WHERE user_id = $1",[params[:id]])

  names = run_sql("SELECT first_name, last_name FROM users WHERE id = $1", [params[:id]])

  username = "#{names[0]['first_name']} #{names[0]['last_name']}"

  erb :trade_history, locals: { history: history, username: username }
end

##################     messages     ######################
##################                  ######################


def get_username_by_id(id)
  result = run_sql("SELECT first_name FROM users Where id = $1",[id])
  first_name = result[0]['first_name']

  return first_name
end

def get_messages
  messages = run_sql("SELECT * FROM messages")

  return messages
end

post '/messages' do
  redirect '/login' unless logged_in? # send to login if not logged in.

  run_sql("INSERT INTO messages (chat, user_id) VALUES ($1, $2);", [params[:message], session[:user_id]])

  redirect '/'
end


