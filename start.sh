

erl -pa ebin deps/*/ebin -s push \
	-eval "io:format(\"see http://localhost:8080~n\")." \
	-extra "root" "" "localhost" "3306" "techno_mt4"