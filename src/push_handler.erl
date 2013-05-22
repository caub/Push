
%% Feel free to use, reuse and abuse the code in this file.

-module(push_handler).

-export([init/4, stream/3, info/3, terminate/2]).

init(_Transport, Req, _Opts, _Active) ->
	{Path, Req2} = cowboy_req:path_info(Req),
	parse_sub(decode(Path), {0, {[],dict:new()}}, Req2).

stream(<<"ping">>, Req, State) ->
	reply(<<"[10, 0, 0]">>, Req, State);
stream(Str, Req, State) ->
	%{Url, _} = cowboy_req:path(Req),
	io:format("stream ~p ~p~n",[self(), Str]),
	%maybe ets:match_delete(subscribers, {'_', self()}),

	parse_sub(decode(Str), State, Req).

parse_sub([Items], State, Req) ->
	ets:insert(subscribers, lists:zip(Items, lists:duplicate(length(Items), self())) ),
	{ok, Req, State};
parse_sub([Items, NewP], {OldP, C}, Req) ->
	ets:insert(subscribers, lists:zip(Items, lists:duplicate(length(Items), self())) ),
	NewP_ = update_p(smooth_period(NewP), OldP),
	{ok, Req, {NewP_, C}};
parse_sub([<<"check">>, User, Port, Ip, Pw], State, Req) when is_integer(User) andalso is_integer(Port) ->
	Matches = ets:match_object(providers, {'_', 2, '_'}),
	D = <<11, User:32/little, Port:32/little, (byte_size(Ip)), Ip/binary, (byte_size(Pw)), Pw/binary>>,
	lists:foreach(fun({Pid,_,_}) -> Pid ! {send, D} end, Matches),
	ets:insert(subscribers, {User, self()} ),
	{ok, Req, State};
parse_sub([<<"close">>, Broker_id, User, Ticket, Ratio, Pw], State, Req) when is_integer(Broker_id) andalso is_integer(User) andalso is_integer(Ticket) andalso is_integer(Ratio) ->
	Matches = ets:match_object(providers, {'_', 0, Broker_id}),
	D = <<13, User:32/little, 1, 0,0,0,0,0,0, 0,   Ticket:32/little, Ratio:32/little, (byte_size(Pw)), Pw/binary>>,
	lists:foreach(fun({Pid,_,_}) -> Pid ! {send, D} end, Matches),
	{ok, Req, State};
parse_sub([<<"open">>, Broker_id, User, Symbol, Op, Lots, Mn, Pw], State, Req) when is_integer(Broker_id) andalso is_integer(User) andalso is_integer(Op) andalso is_integer(Lots) andalso is_integer(Mn) ->
	Matches = ets:match_object(providers, {'_', 0, Broker_id}),
	D = <<13, User:32/little, 0, Symbol:6/binary, Op, Lots:32/little, Mn:32/little, (byte_size(Pw)), Pw/binary>>,
	lists:foreach(fun({Pid,_,_}) -> Pid ! {send, D} end, Matches),
	{ok, Req, State};
parse_sub([<<"list">>, Broker_id, User], State, Req) when is_integer(Broker_id) andalso is_integer(User) ->
	Matches = ets:match_object(providers, {'_', '_', Broker_id}),% tests
	D = <<14, User:32/little>>,
	lists:foreach(fun({Pid,_,_}) -> Pid ! {send, D} end, Matches),
	{ok, Req, State};
parse_sub([18, Name, Pw], State, Req) ->
	case ets:lookup(users, Name) of
		[{_,_P,Ct}] when Ct>100 -> reply(<<"[18,-1]">>, Req, State);
		[{_,P,_Ct}] when P==Pw -> reply(<<"[18,1]">>, Req, State);
		[{_,_P,Ct}] -> ets:update_element(users, Name, {3,Ct+1}),reply(<<"[18,0]">>, Req, State);
		_ -> reply(<<"[18,-2]">>, Req, State)
	end;
parse_sub(D, State, Req) ->
	io:format("? ~p ~p~n ~p~n",[self(),D, State]),
	{ok, Req, State}.


info(refresh, Req, State={0, _}) ->
	{ok, Req, State};
info(refresh, Req, {Period, {C1,C2}}) ->
	_ = erlang:send_after(Period, self(), refresh),

	% Millis = recv_protocol:get_millis(),
	% Data = lists:foldl( fun(Item=[B,U], Acc) ->
	% 	case ets:lookup(cache, Item) of
	% 		[{_, Ms, Infos}] when Ms >= Millis - Period ->
	% 			[[B, U, ets:select(cache,[{{{Item,'_'},'$1'},[],['$1']}]) | Infos] | Acc];
	% 		_ ->
	% 			Acc
	% 	end
	% end, [], Items),
	
	% case Data of
	% 	[] -> 
	% 		{ok, Req, State};
	% 	_ ->
	% 		reply(jsx:encode([8|Data]), Req, State)
	% end;
	Data = dict:fold(fun({[Broker,User],Symbol}, V, Acc) ->
		[[8, Broker,User,Symbol | V] | Acc]
	end,  lists:sort(C1), C2),
	reply(jsx:encode([13|Data]), Req, {Period, {[],dict:new()}});
info({list,D}, Req, State) ->
	reply(D, Req, State); % forward (already encoded)
info(D, Req, State={0, _}) -> % when is_list(D)
	reply(jsx:encode(D), Req, State); % forward all in async mode
info([8, Broker,User,Symbol | V], Req, {Per, {C1,C2}}) ->
	{ok, Req, {Per, {C1, dict:store({[Broker,User], Symbol}, V, C2)}}};
info(D, Req, {Per, {C1,C2}}) ->
	{ok, Req, {Per, {[D|C1],C2}}}.


reply(Data, Req, State) ->
	case cowboy_req:qs_val(<<"callback">>, Req) of
		{undefined, _} ->
			{reply, Data, Req, State};
		{Callback, _} ->
			{reply, [Callback, <<"(">>, Data, <<");">>],
				cowboy_req:set_resp_header(
					<<"content-type">>,<<"application/javascript">>,Req), State}
	end.

terminate(_Req, _State) ->
	%io:format("bullet terminate~p~n",[self()]),
	ets:match_delete(subscribers, {'_', self()}),
	ok.

decode([Json]) -> try jsx:decode(Json) catch _:_ -> [] end;
decode([_, Json]) -> try jsx:decode(Json) catch _:_ -> [] end;
decode([]) -> [];
decode(Json) -> try jsx:decode(Json) catch _:_ -> io:format("sub? ~p~n",[Json]), [] end.

update_p(0, 0) -> 0;
update_p(NewP,0) -> erlang:send_after(NewP, self(), refresh), NewP;
update_p(NewP, _) -> NewP.

smooth_period(Period) when not is_integer(Period) -> 0;
smooth_period(Period) when Period =< 0 -> 0;
smooth_period(Period) when Period < 50 -> 50;
smooth_period(Period) when Period > 5000 -> 5000;
smooth_period(Period) -> Period.

