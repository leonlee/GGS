%% @doc This module is responsible for running the game VM:s. You can issue
%% commands to a vm using this module.

-module(ggs_gamevm_p).
-behaviour(gen_server).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-record(state, { port, table } ).

%% API
-export([start_link/1, define/2, player_command/4, stop/1, call_js/2]).


%% ----------------------------------------------------------------------
% API implementation

%% @doc Create a new VM process. The process ID is returned and can be used
%% with for example the define method of this module.
start_link(Table) ->
    erlang_js:start(), %% @TODO: should only be done once
    {ok, Pid} = gen_server:start_link(?MODULE, [Table], []),
    Pid.

%% @doc Define some new code on the specified VM, returns the atom ok.
define(GameVM, SourceCode) ->
    gen_server:cast(GameVM, {define, SourceCode}).

%% @doc Execute a player command on the specified VM. This function is
%% asynchronous, and returns ok.
%% @spec player_command(GameVM, User, Command, Args) -> ok
%%      GameVM  = process IS of VM
%%      Player  = the player running the command
%%      Command = a game command to run
%%      Args    = arguments for the Command parameter
player_command(GameVM, Player, Command, Args) ->
    gen_server:cast(GameVM, {player_command, Player, Command, Args}).

%% @private
% only for tests
call_js(GameVM, SourceCode) ->
    gen_server:call(GameVM, {eval, SourceCode}).
    
% @doc stops the gamevm process
stop(GameVM) ->
    gen_server:cast(GameVM, stop).


%% ----------------------------------------------------------------------

%% @private
init([Table]) ->
    process_flag(trap_exit, true),
    {ok, Port} = js_driver:new(),
	{ok, JSAPISourceCode} = file:read_file("src/ggs_api.js"),
	ok = js:define(Port, JSAPISourceCode),
	InitGGSJSString = "var GGS = new _GGS(" ++ Table ++ ");",
	ok = js:define(Port, list_to_binary(InitGGSJSString)),
    {ok, #state { port = Port, table = Table }}.

%% private
% only needed for the tests
handle_call({eval, SourceCode}, _From, #state { port = Port } = State) ->
    {ok, Ret} = js:eval(Port, list_to_binary(SourceCode)),
    {reply, Ret, State}.

%% @private    
handle_cast({define, SourceCode}, #state { port = Port, table = Table } = State) ->
    Ret = js:define(Port, list_to_binary(SourceCode)),
	case Ret of
		ok ->
			ggs_table:notify_all_players(Table, {"defined", "ok"}),
			{noreply, State};
		Other ->
			ggs_table:notify_all_players(Table, {"defined", "error " ++ Other}),
			{noreply, State}
	end;
handle_cast({player_command, Player, Command, Args}, #state { port = _Port, table = Table } = State) ->
	intern_player_command(Table, Player, Command, Args),
    {noreply, State};
handle_cast(stop, State) ->
    {stop, normal, State};
handle_cast(Msg, S) ->
    error_logger:error_report([unknown_msg, Msg]),
    {noreply, S}.

%% @private
handle_info(Msg, S) ->
    error_logger:error_report([unknown_msg, Msg]),
    {noreply, S}.

%% @private
terminate(_Reason, _State) ->
    ok.

%% @private
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%js_escape(S) ->
%	lists:flatmap(fun($\') -> [$\\, $\']; (X) -> [X] end, S).
	
	
intern_player_command(Table, Player, Command, _Args) ->
	case Command of
		"ready" ->
			intern_add_player(Table, Player);
		"up" ->
			intern_up(Table, Player);
		"down" ->
			intern_down(Table, Player);
		"start" ->
			intern_start(Table, Player)
	end.
	
intern_add_player(Table, Player) ->
	{ok, PlayerList} = ggs_table:get_player_list(Table),
	case length(PlayerList) of
	    1 -> ok;
	        %erlang:display("A player joined");
		2 ->
            %erlang:display("Player 2 joined"),
            [P1,P2] = PlayerList,
            %erlang:display(PlayerList),
			%erlang:display("P1: joining"),
			ggs_db:setItem(Table, local_storage, P1, player1),
			%erlang:display(ggs_db:getItem(Table, local_storage, P1)),
			ggs_db:setItem(Table, local_storage, player1_y, 50),
			ggs_table:send_command(Table, P1, {"welcome", int2str(1)}),
			ggs_table:notify_all_players(Table, {"player1_y", int2str(50)}),
			%erlang:display("P2: joining"),
			ggs_db:setItem(Table, local_storage, P2, player2),
			%erlang:display(ggs_db:getItem(Table, local_storage, P2)),
			ggs_db:setItem(Table, local_storage, player2_y, 50),
			ggs_table:send_command(Table, P2, {"welcome", int2str(2)}),
			ggs_table:send_command(Table, P2, {"player1_y", int2str(50)}),
			ggs_table:notify_all_players(Table, {"player2_y", int2str(50)});
		_Other ->
			ggs_table:send_command(Table, Player, {"not_welcome", ""})
	end.
			

intern_up(Table, Player) ->
	case ggs_db:getItem(Table, local_storage, Player) of
		player1 ->
			%erlang:display("P1: command up"),
			Y = ggs_db:getItem(Table, local_storage, player1_y),
			NewY = Y - 10,
			case NewY >= 0 of
				true ->
					ggs_db:setItem(Table, local_storage, player1_y, NewY),
					ggs_table:notify_all_players(Table, {"player1_y", int2str(NewY)});
				_Other ->
					ggs_table:send_command(Table, Player, {"notice", "Already on top"})
			end;
		player2 ->
			%erlang:display("P2: command up"),
			Y = ggs_db:getItem(Table, local_storage, player2_y),
			NewY = Y - 10,
			case NewY >= 0 of
				true ->
					ggs_db:setItem(Table, local_storage, player2_y, NewY),
					ggs_table:notify_all_players(Table, {"player2_y", int2str(NewY)});
				_Other ->
					ggs_table:send_command(Table, Player, {"notice", "Already on top"})
			end
	end.		
	
intern_down(Table, Player) ->
	case ggs_db:getItem(Table, local_storage, Player) of
		player1 ->
			%erlang:display("P1: command down"),
			Y = ggs_db:getItem(Table, local_storage, player1_y),
			NewY = Y + 10,
			case NewY =< 100 of
				true ->
					ggs_db:setItem(Table, local_storage, player1_y, NewY),
					ggs_table:notify_all_players(Table, {"player1_y", int2str(NewY)});
				_Other ->
					ggs_table:send_command(Table, Player, {"notice", "Already on bottom"})
			end;
		player2 ->
			%erlang:display("P2: command down"),
			Y = ggs_db:getItem(Table, local_storage, player2_y),
			NewY = Y + 10,
			case NewY =< 100 of
				true ->
					ggs_db:setItem(Table, local_storage, player2_y, NewY),
					ggs_table:notify_all_players(Table, {"player2_y", int2str(NewY)});
				_Other ->
					ggs_table:send_command(Table, Player, {"notice", "Already on bottom"})
			end
	end.
	
intern_start(Table, Player) ->
    %erlang:display(Player),
    %erlang:display(ggs_db:getItem(Table, local_storage, Player)),
	case ggs_db:getItem(Table, local_storage, Player) of
		player1 ->
			ggs_db:setItem(Table, local_storage, player1_ready, true),
			ggs_db:setItem(Table, local_storage, player1_points, 0),
			case ggs_db:getItem(Table, local_storage, player2_ready) of
				true ->
					%erlang:display("P1 ready, start game."),
					ggs_table:notify_all_players(Table, {"game", "start"}),
					ggs_db:setItem(Table, local_storage, ball, {50,50,1,1}),
					Pid = spawn(fun() -> game_loop([Table]) end),
					Pid ! tick;
				_Other ->
					%erlang:display("P1 ready, waiting."),
					ggs_table:send_command(Table, Player, {"game", "wait"})
			end;
		player2 ->
			ggs_db:setItem(Table, local_storage, player2_ready, true),
			ggs_db:setItem(Table, local_storage, player2_points, 0),
			case ggs_db:getItem(Table, local_storage, player1_ready) of
				true ->
					%erlang:display("P2 ready, start game."),
					ggs_table:notify_all_players(Table, {"game", "start"}),
					ggs_db:setItem(Table, local_storage, ball, {50,50,-1,-1}),
					GameLoop = spawn(fun() -> game_loop([Table]) end),
					GameLoop ! tick;
				_Other ->
					%erlang:display("P2 ready, waiting."),
					ggs_table:send_command(Table, Player, {"game", "wait"})
			end;
		_Other ->
			ok
		    %erlang:display(Other)
	end.
	
game_loop([Table]) ->
	receive
		tick ->
			{BX, BY, SX, SY} = step_ball(ggs_db:getItem(Table, local_storage, ball)),
			Ball = {BX, BY, SX, SY},
			ggs_db:setItem(Table, local_storage, ball, Ball),
			ggs_table:notify_all_players(Table, {"ball", int2str(BX) ++ "," ++ int2str(BY)}),
			check_ball(Table, Ball),
			timer:send_after(50, tick),
			game_loop([Table]);
		'EXIT' ->
			exit(normal)
	end.

int2str(Int) ->
	lists:flatten(io_lib:format("~p", [Int])).
	
step_ball({BX, BY, SX, SY}) ->
	Ball = {BX + SX, BY + SY, SX, SY},
	Ball.
	
check_ball(Table, {BX, BY, SX, SY}) ->
	% check up and down bounds
	case (BY > 90) or (BY < 0) of
		true ->
			NewSY = -SY;
		false ->
			NewSY = SY
	end,
	
	% check intersection with a player
	P1Y = ggs_db:getItem(Table, local_storage, player1_y),
	P2Y = ggs_db:getItem(Table, local_storage, player2_y),
	case (check_intersect({0, P1Y, 10, 30}, {BX, BY, 10, 10}) or check_intersect({99, P2Y, 10, 30}, {BX, BY, 10, 10})) of
		true ->
			NewSX = -SX,
			case NewSX of
				-1 ->
					ggs_table:notify_all_players(Table, {"sound", "ping"});
				1 ->
					ggs_table:notify_all_players(Table, {"sound", "pong"})
			end;
		false ->
			NewSX = SX
	end,
	ggs_db:setItem(Table, local_storage, ball, {BX, BY , NewSX, NewSY}),


	% check for point player1
	case BX > 100 of
		true ->
			Player1Points = ggs_db:getItem(Table, local_storage, player1_points),
			NewPlayer1Points = Player1Points + 1,
			ggs_db:setItem(Table, local_storage, player1_points, NewPlayer1Points),
			ggs_table:notify_all_players(Table, {"player1_points", int2str(NewPlayer1Points)}),
			exit(normal);
		false ->
			ok
	end,

	% check for point player2
	case BX < 0 of
		true ->
			Player2Points = ggs_db:getItem(Table, local_storage, player2_points),
			NewPlayer2Points = Player2Points + 1,
			ggs_db:setItem(Table, local_storage, player2_points, NewPlayer2Points),
			ggs_table:notify_all_players(Table, {"player2_points", int2str(NewPlayer2Points)}),
			exit(normal);
		false -> 
			ok
	end.


check_intersect({AX1, AY1, AW, AH}, {BX1, BY1, BW, BH}) ->
	AX2 = AX1 + AW,
	AY2 = AY1 + AH,
	BX2 = BX1 + BW,
	BY2 = BY1 + BH,
	(AX1 < BX2) and (AX2 > BX1) and (AY1 < BY2) and (AY2 > BY1).
