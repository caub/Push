%% Feel free to use, reuse and abuse the code in this file.

-module(recv_ping_protocol).
-export([start_link/4, init/4]).

start_link(Ref, Socket, Transport, Opts) ->
	Pid = spawn_link(?MODULE, init, [Ref, Socket, Transport, Opts]),
	{ok, Pid}.

init(Ref, Socket, Transport, _Opts) ->
	ok = ranch:accept_ack(Ref),
	_ = erlang:send_after(5000, self(), ping),
	loop1(Socket, Transport).

loop1(Socket, Transport) ->
	{OK, Closed, Error} = Transport:messages(),
	Transport:setopts(Socket, [{active, once}]),
	receive
		% {OK, Socket, <<0, _Mode:8, _Broker:8>>} ->
		% 	Transport:send(Socket, <<1>>),
		% 	loop1(Socket, Transport);
		{OK, Socket, <<1, Mode:8, Broker:32/little>>} ->
			ets:insert(providers, {self(), Mode, Broker}),
			loop1(Socket, Transport);
		{OK, Socket, _Data} ->
			loop1(Socket, Transport);
		{Closed, Socket} ->
			io:format("socket got closed~n"),
			ets:delete(providers, self());
		{Error, Socket, Reason} ->
			io:format("error happened: ~p~n", [Reason]),
			ok = Transport:close(Socket);
		{send, Data} ->
			Transport:send(Socket, Data),
			loop1(Socket, Transport);
		ping ->
			_ = erlang:send_after(5000, self(), ping),
			Transport:send(Socket, <<1>>),
			loop1(Socket, Transport);
		stop ->
			io:format(" bye~n"),
			Transport:send(Socket, <<0>>),
			ok = Transport:close(Socket),
			loop1(Socket, Transport)
	end.
