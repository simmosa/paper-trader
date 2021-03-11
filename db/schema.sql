


INSERT INTO planets (name, image_url, diameter, mass, moon_count) VALUES ('Earth', 'https://www.nasa.gov/centers/goddard/images/content/638831main_globe_east_2048.jpg', 12742, 5.972, 1);


CREATE DATABASE trading_floor;

\c trading_floor

CREATE TABLE trades (
    id SERIAL PRIMARY KEY,
    price decimal(10,2),
    no_of_coins decimal(12,8),
    trade_size decimal(10,2),
    user_id INTEGER
);



CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    first_name TEXT,
    last_name TEXT,
    email TEXT,
    password_digest TEXT
);


INSERT INTO users (first_name, last_name, email, password_digest) VALUES ('Simo', 'Raj', 'simo@simo.co','pancake');

INSERT INTO users (email, password) VALUES ('simo@simo.co', 'pancake');
INSERT INTO users (email, password) VALUES ('simo2@simo.co', 'pancake2');