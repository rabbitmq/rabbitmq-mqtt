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

-module(rabbit_mqtt_connection_sup).

-behaviour(supervisor).
-behaviour(ranch_protocol).

-include_lib("rabbit_common/include/rabbit.hrl").

-export([start_link/4, start_keepalive_link/0]).

-export([init/1]).

%%----------------------------------------------------------------------------

start_link(Ref, _Sock, _Transport, []) ->
    {ok, SupPid} = supervisor:start_link(?MODULE, []),
    {ok, KeepaliveSup} = supervisor:start_child(SupPid,
                          #{
                              id       => rabbit_mqtt_keepalive_sup,
                              start    => {rabbit_mqtt_connection_sup, start_keepalive_link, []},
                              restart  => transient,
                              shutdown => infinity,
                              type     => supervisor,
                              modules  => [rabbit_keepalive_sup]
                          }),
    {ok, ReaderPid} = supervisor:start_child(SupPid,
                        #{
                            id       => rabbit_mqtt_reader,
                            start    => {rabbit_mqtt_reader, start_link, [KeepaliveSup, Ref]},
                            restart  => transient,
                            shutdown => ?WORKER_WAIT,
                            type     => worker,
                            modules  => [rabbit_mqtt_reader]
                        }),
    {ok, SupPid, ReaderPid}.

start_keepalive_link() ->
    supervisor:start_link(?MODULE, []).

%%----------------------------------------------------------------------------

init([]) ->
    {ok, {{one_for_all, 0, 1}, []}}.


