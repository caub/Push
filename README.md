
install
===

you need [rebar](https://github.com/basho/rebar) package manager, to build the project

run `rebar get-deps compile`  
start it with `sh start.sh`
open test.htm 


settings
===
in start.sh:

 "db_user" "db_pass" "db_host" "db_port" "db_name"  
 %% optional 6th arg: "c:/path/to/MT4.exe", by default "../MT4/bin/Debug/MT4.exe"

