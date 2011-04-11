%%% @doc This module handles TCP incomming and outcommint.

-module(ggs_protocol).
-export([start_link/2,stop/1]).
-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).
%% Old 
-export([parse/1, getToken/1, create_message/4, send_command/2]).

-vsn(1.0).

-record(state, {
    player, 
    socket, 
    header_string, 
    header_list, 
    body, 
    content_length}).

start_link(Socket, Player) ->
    gen_server:start_link(?MODULE, {Socket, Player}, []).
    
stop(Protocol) ->
    gen_server:cast(Protocol, stop).
    
send_command(Protocol, {Command, Data}) ->
    gen_server:cast(Protocol, {send, Command, Data}).

init({Socket, Player}) ->
    erlang:port_connect(Socket, self()),
    State = #state{
        socket = Socket,
        player = Player,
        header_list = [],
        header_string = "",
        body = "",
        content_length = -1
    },
    {ok, State}.

handle_cast({tcp, _Socket, Data}, State) ->
    case State#state.content_length of
        -1 -> % its a header
            TmpHeader = State#state.header_string ++ Data,
            case string:str(TmpHeader, "\n\n") of
                0 -> % still in header
                    {reply, ok, State # state {header_string = TmpHeader}};
                _ -> % we left the header
                    {Header, Body} = parse(TmpHeader),
                    {_, ContentLengthString} = lists:keyfind(content_len, 1, Header), % find Content-Length
                    {ContentLength, []} = string:to_integer(ContentLengthString),
                    {reply, ok, State#state{
                        header_list = Header,
                        header_string = "",
                        body = Body,
                        content_length = ContentLength}}
            end;
        Length -> % its a body
            LBody = string:len(State#state.body),
            LData = string:len(Data),
            NewLength = LBody + LData,
            if
                NewLength < Length -> %  not enough data
                    Body = State#state.body ++ Data,
                    {reply, ok, State#state {body = Body}};
                NewLength > Length -> % too much data
                    EndOfMessagePos = LBody + LData - Length,
                    Body = State#state.body ++ string:substr(Data, 0, EndOfMessagePos),
                    NextHeader = string:substr(Data, EndOfMessagePos, LData),
                    Message = prettify(State#state.header_list, Body),
                    gen_player:notify_game(State#state.player, Message),
                    {reply, ok, State#state {
                        header_string = NextHeader,
                        header_list = [],
                        body = "",
                        content_length = -1}};
                NewLength == Length -> % end of message
                    Message = prettify(State#state.header_list, State#state.body ++ Data),
                    gen_player:notify_game(State#state.player, Message),                    
                    {reply, ok, State#state {
                        header_string = "",
                        header_list = [],
                        body = "",
                        content_length = -1}}
            end
    end;

handle_cast({send, Command, Data}, State) -> 
    Message = create_message(Command, "text", "text", Data),
    gen_tcp:send(State#state.socket, Message),
    {noreply, State};

handle_cast(_Request, St) -> {stop, unimplemented, St}.
handle_call(_Request, _From, St) -> {stop, unimplemented, St}.

handle_info(_Info, St) -> {stop, unimplemented, St}.


terminate(_Reason, _St) -> ok.
code_change(_OldVsn, St, _Extra) -> {ok, St}.



%% API Functions
parse(Data) ->
    do_parse(Data, []).
    
getToken(Parsed) ->
    case lists:keyfind(token, 1, Parsed) of
        {_, Value} ->
            Value;
        false ->
            false
    end.
    


create_message(Cmd, Enc, Acc, Data) ->
    Length = integer_to_list(string:len(Data)),
    Msg =   "Client-Command: " ++ Cmd ++ "\n" ++
            "Client-Encoding: " ++ Enc ++ "\n" ++
            "Content-Size: " ++ Length ++ "\n" ++
            "GGS-Version: 1.0\n" ++
            "Accept: " ++ Acc ++ "\n" ++
            "\n" ++
            Data,
    Msg.

%% Internal helpers
do_parse(Data, Headers) ->
    NewLinePos = string:chr(Data, $\n),
    Line = string:substr(Data, 1, NewLinePos-1),
    Tokens = re:split(Line, ": ", [{return, list}]),
    case handle(Tokens) of
        {Command, more} ->
            do_parse(string:substr(Data, NewLinePos+1), Headers ++ [Command]);
        {separator, data_next} ->
            {Headers, Data}
    end.

handle([[]]) ->
    {separator, data_next};
handle(["Server-Command", Param]) ->
    {{srv_cmd, Param}, more};
handle(["Game-Command", Param]) ->
    {{game_cmd, Param}, more};
handle(["Content-Length", Param]) ->
    {{content_len, Param}, more};
handle(["Token", Param]) ->
    {{token, Param}, more};
handle(["Content-Type", Param]) ->
    {{content_type, Param}, more}.

%handle_data(Data, Length) ->
%    {data, string:substr(Data,1,Length)}.


prettify(Args, Data) ->
    case lists:keyfind(srv_cmd, 1, Args) of
        {_, Value} ->
            {srv_cmd, Value, Args, Data};
        _Other ->
            case lists:keyfind(game_cmd, 1, Args) of
                {_, Value} ->
                    {game_cmd, Value, Args, Data};
                _ ->
                    ok
            end
    end.

