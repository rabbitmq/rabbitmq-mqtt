%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at https://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ.
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2020 VMware, Inc. or its affiliates.  All rights reserved.
%%

-module(rabbit_mqtt_retainer).

-behaviour(gen_server2).
-include("rabbit_mqtt.hrl").
-include("rabbit_mqtt_frame.hrl").

-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3, start_link/2]).

-export([retain/3, fetch/2, clear/2, store_module/0]).

-define(SERVER, ?MODULE).
-define(TIMEOUT, 30000).

-record(retainer_state, {store_mod,
                         store}).

-spec retain(pid(), string(), mqtt_msg()) ->
    {noreply, NewState :: term()} |
    {noreply, NewState :: term(), timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: term()}.

%%----------------------------------------------------------------------------

start_link(RetainStoreMod, VHost) ->
    gen_server2:start_link(?MODULE, [RetainStoreMod, VHost], []).

retain(Pid, Topic, Msg = #mqtt_msg{retain = true}) ->
    gen_server2:cast(Pid, {retain, Topic, Msg});

retain(_Pid, _Topic, Msg = #mqtt_msg{retain = false}) ->
    throw({error, {retain_is_false, Msg}}).

fetch(Pid, Topic) ->
    gen_server2:call(Pid, {fetch, Topic}, ?TIMEOUT).

clear(Pid, Topic) ->
    gen_server2:cast(Pid, {clear, Topic}).

%%----------------------------------------------------------------------------

init([StoreMod, VHost]) ->
    process_flag(trap_exit, true),
    State = case StoreMod:recover(store_dir(), VHost) of
                {ok, Store} -> #retainer_state{store = Store,
                                               store_mod = StoreMod};
                {error, _}  -> #retainer_state{store = StoreMod:new(store_dir(), VHost),
                                               store_mod = StoreMod}
            end,
    {ok, State}.

store_module() ->
    case application:get_env(rabbitmq_mqtt, retained_message_store) of
        {ok, Mod} -> Mod;
        undefined -> undefined
    end.

%%----------------------------------------------------------------------------

handle_cast({retain, Topic, Msg},
    State = #retainer_state{store = Store, store_mod = Mod}) ->
    ok = Mod:insert(Topic, Msg, Store),
    {noreply, State};
handle_cast({clear, Topic},
    State = #retainer_state{store = Store, store_mod = Mod}) ->
    ok = Mod:delete(Topic, Store),
    {noreply, State}.

handle_call({fetch, Topic}, _From,
    State = #retainer_state{store = Store, store_mod = Mod}) ->
    Reply = case Mod:lookup(Topic, Store) of
                #retained_message{mqtt_msg = Msg} -> Msg;
                not_found                         -> undefined
            end,
    {reply, Reply, State}.

handle_info(stop, State) ->
    {stop, normal, State};

handle_info(Info, State) ->
    {stop, {unknown_info, Info}, State}.

store_dir() ->
    rabbit_mnesia:dir().

terminate(_Reason, #retainer_state{store = Store, store_mod = Mod}) ->
    Mod:terminate(Store),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
