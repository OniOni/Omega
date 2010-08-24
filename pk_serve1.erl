-module(pk_serve1).
-author("Mathieu Sabourin").

-export([listen/1, start/1, spine/1]).

-define(TCP_OPTIONS, [binary, {packet, 0}, {active, once}, {reuseaddr, true}]).

spine(start) ->
    D = dict:new(),
    spine(D);

spine(D) ->
    receive
	{get, Pid} ->
	    Pid ! D,
	    D1 = D;
	{Key, Value} ->
	    D1 = dict:store(Key, Value, D)
    end,
    spine(D1).

to_from({Key, Value, Spine}, dict)->
    Spine ! {self(), Key, Value},
    receive
	D ->
	    io:format("In to_from~n D -> ~p~n", [dict:to_list(D)])
    end,
    D;

to_from({Key, Value, Spine}, list) ->
    dict:to_list(to_from({Key, Value, Spine}, dict)).

pk_set({Key, Value}, Spine) ->
    Spine ! {Key, Value}.

pk_get(Spine) ->
    Spine ! {get, self()},
    receive
	D ->
	    io:format("In pk_get~n D -> ~p~n", [dict:to_list(D)])
    end,
    dict:to_list(D).

listen(Port) ->
    {ok, LSocket} = gen_tcp:listen(Port, ?TCP_OPTIONS),
    Pid = spawn(?MODULE, spine, [start]),
    accept(LSocket, Pid).

accept(LSocket, Pid) ->
    {ok, Socket} = gen_tcp:accept(LSocket),
    inet:setopts(Socket, ?TCP_OPTIONS),
    spawn(fun() -> accept(LSocket, Pid) end),
    loop(Socket, Pid),
    gen_tcp:close(Socket).

parse(Str)->
    S = Str ++ ".",
    {ok, Tks,_} = erl_scan:string(S),
    {ok, T} = erl_parse:parse_term(Tks),
    io:format("~p~n", [T]),
    T. 

cmd(Input) ->
    case string:sub_word(Input, 1) of
	"set" ->
	    {set, Input -- "set "};
	"get"  ->
	    {get, Input -- "get "}
    end.
            
loop(Socket, Pid) ->
    inet:setopts(Socket, [{active, once}]),
    %case gen_tcp:recv(Socket, 0) of
    receive
        {tcp, Socket, Data} ->
	    case bitstring_to_list(Data) of
		[$s, $e, $t | Coord] ->
		    KV = parse(Coord -- " "),
		    pk_set(KV, Pid);
		[$g, $e, $t | _] ->
		    gen_tcp:send(Socket, io_lib:format("~p~n", [pk_get(Pid)]))
	    end,
	    loop(Socket, Pid);
        {tcp_closed, Socket} ->
            ok
    end.

start(test) ->
    start(8888);
start(Socket) ->
    spawn(?MODULE, listen, [Socket]).
