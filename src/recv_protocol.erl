%% Feel free to use, reuse and abuse the code in this file.

-module(recv_protocol).
-export([start_link/4, init/4]).

-export([get_millis/0]).

start_link(Ref, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
	{ok, Pid}.

init(Ref, Socket, Transport, _Opts) ->
	ok = ranch:accept_ack(Ref),
	%{_, Pid} = lists:keyfind(main, 1, Opts),
	loop(Socket, Transport).

loop(Socket, Transport) ->
	case Transport:recv(Socket, 0, infinity) of
		{ok, Data} ->
			parse(Data),
			loop(Socket, Transport);
		_ ->
			io:format("closed socket~n"),
			ok = Transport:close(Socket)
	end.


parse(<<>>) ->
	ok;

parse(<<8, Broker:32/little, User:32/little, B:32/little, Eq:32/little, M:32/little, Fm:32/little, Ps:32/signed-little,
			P:32/little, L:32/little, C:32/little, Symbol:6/binary, T:19/binary, N, Pnls:N/binary-unit:104, Tail/binary>>) ->

	Pnls2 = [ [Ticket,Type,Pr/100,Sw/100] || <<Ticket:32/little, Type, Pr:32/signed-little, Sw:32/signed-little>> <= Pnls],
	Data = [8, Broker, User, Symbol, Pnls2, B/100, Eq/100, M/100, Fm/100, Ps/100, P/100, L, C/100, T],

	Followers = ets:lookup(subscribers, [Broker,User]),
	lists:foreach(fun({_,Pid}) -> Pid ! Data end, Followers), % notify push_handlers

	%%ets:insert(cache, { {[Broker,User], Symbol}, Pnls2 }),
	%%ets:insert(cache, { [Broker,User], get_millis(), [B/100, Eq/100, M/100, Fm/100, Ps/100, P/100, L, C/100, T] }),
	
	parse(Tail);

parse(<<11, C, User:32/little, S:32/little, B:32/little, E:32/little, M:32/little, F:32/little, L, Msg:L/binary, Tail/binary>>) ->
	Data = [11, C, S, B/100, E/100, M/100, F/100, Msg],
	Followers = ets:lookup(subscribers, User),
	lists:foreach(fun({_,Pid}) -> Pid ! Data end, Followers),
	parse(Tail);

parse(<<14, Broker:32/little, User:32/little, L:32/little, Data:L/binary, Tail/binary>>) ->
	Followers = ets:lookup(subscribers, [Broker,User]),
	lists:foreach(fun({_,Pid}) -> Pid ! {list,Data} end, Followers), %already a Json
	parse(Tail);
parse(<<9, Broker:32/little, User:32/little, L:32/little, Log:L/binary, Tail/binary>>) ->
	Data = [9, Broker, User, Log],
	Followers = ets:lookup(subscribers, [Broker,User]),
	lists:foreach(fun({_,Pid}) -> Pid ! Data end, Followers),
	parse(Tail);

parse(<<Action, Broker:32/little, User:32/little, C, Type, Ticket:32/little, Mn:32/little, Algo:32/little, Otime:19/binary,
			Lots:32/little, Symbol:6/binary, Oprice:32/little, Sl:32/little, Tp:32/little, Cprice:32/little, Ctime:19/binary,
			Sw:32/signed-little, Pr:32/signed-little, Csrc, Exp:19/binary, L, Comment:L/binary, Tail/binary>>) -> %% when Action < 8 (maybe?)

	Order = [Action, C, Broker, User, Ticket, Mn, Algo, Otime, Type, Lots/100000, Symbol, Oprice/100000,
					Sl/100000, Tp/100000, Cprice/100000, Ctime, Sw/100, Pr/100, Csrc, Exp, Comment],
	Followers = ets:lookup(subscribers, [Broker,User]),
	lists:foreach(fun({_,Pid}) -> Pid ! Order end, Followers),
	% case Action of
	% 	1 ->
	% 		ets:delete(cache, [Broker,User]),
	% 		ets:delete(cache, {[Broker,User], Symbol}); %it deletes also others in cache :(
	% 	_ ->
	% 		ok
	% end,
	ets:insert(log, {[Broker,Ticket], Order}), % debug
	parse(Tail);

parse(Data) ->
	io:format(" unknown packet ~p~n",[Data]).


get_millis() ->
	{_,S,MS} = os:timestamp(),
	S*1000+(MS div 1000).