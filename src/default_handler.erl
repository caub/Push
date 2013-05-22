%% Feel free to use, reuse and abuse the code in this file.

-module(default_handler).

-export([init/3, handle/2, terminate/3]).

init(_Transport, Req, _Opts) ->
	{ok, Req, '_'}.

handle(Req, _State) ->
	{ok, Req3} = case element(1,cowboy_req:qs_vals(Req)) of
		[{<<"out">>,_}] ->
			Req2 = cowboy_req:set_resp_cookie(
				<<"cowboy">>, [], [{expires, <<"Thu, 01 Jan 1970 00:00:00 GMT">>},{path, <<"/">>}], Req),
			tpl(signin_dtl, [{msg, <<"Please sign in">>}], Req2);
		[{<<"t">>,_}] -> tpl(signin_dtl, [{msg, <<"too many tries, try later">>}], Req);
		[{<<"badpw">>,_}] -> tpl(signin_dtl, [{msg, <<"bad password">>}], Req);
		[{<<"nouser">>,_}] -> tpl(signin_dtl, [{msg, <<"email unknown">>}], Req);
		[{<<"name">>,Name},{<<"pw">>,Pw}] -> auth(Name, Pw, Req);
		[{<<"pw">>,Pw},{<<"name">>,Name}] -> auth(Name, Pw, Req);
		_ -> case cowboy_req:cookie(<<"cowboy">>, Req) of
				{undefined, Req2} -> tpl(signin_dtl, [{msg, <<"Please sign in">>}], Req2);
				{<<>>, Req2} -> tpl(signin_dtl, [{msg, <<"Please sign in">>}], Req2);
				{Name, Req2} -> tpl(default_dtl, [{name, Name}, {list, list_p()}], Req2)
			end
	end,
	{ok, Req3, '_'}.

auth(Name, Pw, Req) ->
	case ets:lookup(users, Name) of
		[{_,_P,Ct}] when Ct>100 -> cowboy_req:reply(302, [{<<"Location">>, <<"/?t">>}], [], Req);
		[{_,P,_Ct}] when P==Pw ->
			Req2 = cowboy_req:set_resp_cookie(
				<<"cowboy">>, Name, [{expires, <<"Wed, 01-Jan-3000 00:00:00 GMT">>},{path, <<"/">>}], Req),
			ets:update_element(users, Name, {3,0}),
			cowboy_req:reply(302, [{<<"Location">>, <<"/">>}], [], Req2);
		[{_,_P,Ct}] ->
			ets:update_element(users, Name, {3,Ct+5}),
			cowboy_req:reply(302, [{<<"Location">>, <<"/?badpw">>}], [], Req);
		_ -> cowboy_req:reply(302, [{<<"Location">>, <<"/?nouser">>}], [], Req)
	end.

tpl(Template, Args, Req) ->
	{Host, _} = cowboy_req:host(Req),
	cowboy_req:reply(200, [], element(2, Template:render([{host, Host} | Args])), Req).

terminate(_Reason, _Req, _State) ->
	ok.

list_p() ->
	ets:foldl(fun({P,M,B}, Acc) ->
			[iolist_to_binary(io_lib:format("~p, mode: ~p, broker: ~p",[P,M,B])) | Acc]
	end, [], providers).

