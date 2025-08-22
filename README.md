# Insurance Management System — Database (MySQL)

This container provisions and runs a local MySQL instance for development and testing. It also generates a convenient mysql.env for use with tooling and a db_connection.txt with a ready-to-copy CLI command.

Environment variables
The database setup script writes the following variables to insurance_management_database/db_visualizer/mysql.env:
- MYSQL_URL
- MYSQL_USER
- MYSQL_PASSWORD
- MYSQL_DB
- MYSQL_PORT

Quick start
1) Start MySQL using the setup script:
   cd insurance_management_database
   bash startup.sh
   The script will initialize MySQL if needed, start it on the configured port, create database and users, and print connection info.
2) Get connection details:
   - See db_connection.txt for a mysql CLI command
   - Source db_visualizer/mysql.env to export MYSQL_* variables for other tools:
     source db_visualizer/mysql.env
3) Connect with CLI:
   $(cat db_connection.txt)

Default configuration
- Database name: myapp
- App user: appuser
- Port: 5000
- The script ensures root and appuser credentials and sets MySQL 8 auth compatibility.

Using with backend
- Configure the backend to connect using MYSQL_URL, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB, MYSQL_PORT. In dev profile, the backend composes a default URL if MYSQL_URL is not provided. For production, set MYSQL_URL explicitly.

Optional: DB Visualizer (Node.js)
A lightweight Node.js tool is included to inspect database schemas and tables.

To run:
1) Ensure Node.js is installed
2) cd insurance_management_database/db_visualizer
3) source mysql.env
4) npm install
5) node server.js
The server exposes a small UI on http://localhost:3001 (or as configured in server.js) to browse connected databases.

Notes
- The script is idempotent: if MySQL is already running, it prints connection info and exits.
- If the port is in use by another MySQL instance, adjust DB_PORT at the top of startup.sh before running.