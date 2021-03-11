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

# def run_sql(sql, arr = []) 
#   db = PG.connect(dbname: 'trading_floor')
#   results = db.exec_params(sql, arr) 
#   db.close
#   return results
# end

def current_user
  results = run_sql("SELECT * FROM users WHERE id = $1;", [session[:user_id]])
  # db = PG.connect(dbname: 'trading_floor')
  # sql = "SELECT * FROM users WHERE id = #{session[:user_id]};"
  # results = db.exec(sql)
  # db.close
  return results.first
end

def record_trade(price, no_of_coins, trade_size)
  run_sql("INSERT INTO trades (price, no_of_coins, trade_size, user_id) VALUES ($1, $2, $3, $4);", [price, no_of_coins, trade_size, session[:user_id]])

  # db = PG.connect(dbname: 'trading_floor')
  # sql = "INSERT INTO trades (price, no_of_coins, trade_size, user_id) VALUES (#{price}, #{no_of_coins}, #{trade_size}, #{session[:user_id]});"
  # db.exec(sql)
  # db.close
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


  # set the session user_id to that of the user id just created
  session[:user_id] = user_id[0]['id']
  redirect '/'
end

get '/users/:id' do
  result = run_sql("SELECT * FROM users WHERE id = $1",[params[:id]])
  user = result[0]

  # db = PG.connect(dbname: 'trading_floor')
  # sql = "SELECT * FROM users WHERE id = '#{params[:id]}';"
  # user = db.exec(sql)[0]
  # db.close

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

  # db = PG.connect(dbname: 'trading_floor')
  # db.exec("DELETE FROM users WHERE id = #{params[:id]};")
  # db.close

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

# def get_cash_balance(user_id)

# end

# def purchase_exceeds_balance(cost)
#   if cost >= cash_balance
# end


get '/' do
  # get the balances to display for the session user or zero balance if not logged in
  cash_balance = 0
  bitcoin_balance = 0

  if logged_in?
    trades = run_sql("SELECT * FROM trades WHERE user_id = $1", [session[:user_id]])
    # calculates balances each time. Would be a scaling issue. Will need to place the balances as a column in users table that updates after each trade, solving the need to traverse the whole trades table each time.
    trades.each do |trade|
      cash_balance = cash_balance + trade['trade_size'].to_f
      bitcoin_balance = bitcoin_balance + trade['no_of_coins'].to_f
    end
  end

  combined_value = cash_balance + (bitcoin_balance * get_btc_price())

  erb :index, locals: { cash_balance: cash_balance, bitcoin_balance: bitcoin_balance, combined_value: combined_value }
end


post '/trade' do
  redirect '/login' unless logged_in? # send to login if not logged in.
  
  price = get_btc_price()

  # convert the trade_cost to -ve if it's not a purchase.
  if params[:purchase]
    trade_cost = params[:trade_amount].to_f.round(2)
    # if purchase_exceeds_balance(trade_cost)
    #   redirect '/'
    # end
  else
    trade_cost = -(params[:trade_amount].to_f.round(2))   
  end

  no_of_bitcoins = (trade_cost / price).round(8)
  record_trade(price, no_of_bitcoins, trade_cost)
  
  redirect '/'
end


get '/trade_history' do
  redirect '/login' unless logged_in? # send to login if not logged in.

  history = run_sql("SELECT * FROM trades WHERE user_id = $1",[session[:user_id]])

  # db = PG.connect(dbname: 'trading_floor')
  # sql = "SELECT * FROM trades WHERE user_id='#{session[:user_id]}';"
  # history = db.exec(sql)
  # db.close

  erb :trade_history, locals: { history: history }
end




