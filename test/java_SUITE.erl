%% The contents of this file are subject to the Mozilla Public License
%% Version 1.1 (the "License"); you may not use this file except in
%% compliance with the License. You may obtain a copy of the License
%% at http://www.mozilla.org/MPL/
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and
%% limitations under the License.
%%
%% The Original Code is RabbitMQ
%%
%% The Initial Developer of the Original Code is GoPivotal, Inc.
%% Copyright (c) 2007-2016 Pivotal Software, Inc.  All rights reserved.
%%

-module(java_SUITE).
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

-define(BASE_CONF_RABBIT, {rabbit, [{ssl_options, [{fail_if_no_peer_cert, false}]}]}).
-define(BASE_CONF_MQTT,
        {rabbitmq_mqtt, [
           {ssl_cert_login,   true},
           {allow_anonymous,  true},
           {tcp_listeners,    []},
           {ssl_listeners,    []}
           ]}).

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                java
                               ]}
    ].

suite() ->
    [{timetrap, {seconds, 600}}].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

merge_app_env(Config) ->
    {ok, Ssl} = q(Config, [erlang_node_config, rabbit, ssl_options]),
    Ssl1 = lists:keyreplace(fail_if_no_peer_cert, 1, Ssl, {fail_if_no_peer_cert, false}),
    Config1 = rabbit_ct_helpers:merge_app_env(Config, {rabbit, [{ssl_options, Ssl1}]}),
    rabbit_ct_helpers:merge_app_env(Config1, ?BASE_CONF_MQTT).

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE},
        {rmq_certspwd, "bunnychow"}
      ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
      [ fun merge_app_env/1 ] ++
      rabbit_ct_broker_helpers:setup_steps() ++
      rabbit_ct_client_helpers:setup_steps()).

end_per_suite(Config) ->
    rabbit_ct_helpers:run_teardown_steps(Config,
      rabbit_ct_client_helpers:teardown_steps() ++
      rabbit_ct_broker_helpers:teardown_steps()).

init_per_group(_, Config) ->
    Config.

end_per_group(_, Config) ->
    Config.

init_per_testcase(Testcase, Config) ->
    Hostname = re:replace(os:cmd("hostname"), "\\s+", "", [global,{return,list}]),
    User = "O=client,CN=" ++ Hostname,
    {ok,_} = rabbit_ct_broker_helpers:rabbitmqctl(Config, 0, ["add_user", User, ""]),
    {ok, _} = rabbit_ct_broker_helpers:rabbitmqctl(Config, 0, ["set_permissions",  "-p", "/", User, ".*", ".*", ".*"]),
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).


%% -------------------------------------------------------------------
%% Testsuite cases
%% -------------------------------------------------------------------

java(Config) ->
    CertsDir = rabbit_ct_helpers:get_config(Config, rmq_certsdir),
    MqttPort = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_mqtt),
    MqttSslPort = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_mqtt_tls),
    AmqpPort = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_amqp),
    DataDir = rabbit_ct_helpers:get_config(Config, priv_dir),
    os:putenv("DATA_DIR", DataDir),
    os:putenv("SSL_CERTS_DIR", CertsDir),
    os:putenv("MQTT_SSL_PORT", erlang:integer_to_list(MqttSslPort)),
    os:putenv("MQTT_PORT", erlang:integer_to_list(MqttPort)),
    os:putenv("AMQP_PORT", erlang:integer_to_list(AmqpPort)),
    {ok, _} = rabbit_ct_helpers:make(Config, make_dir(), ["test"]).


make_dir() ->
    {Src, _} = filename:find_src(?MODULE),
    filename:dirname(Src).

rpc(Config, M, F, A) ->
    rabbit_ct_broker_helpers:rpc(Config, 0, M, F, A).

q(P, [K | Rem]) ->
    case proplists:get_value(K, P) of
        undefined -> undefined;
        V -> q(V, Rem)
    end;
q(P, []) -> {ok, P}.

