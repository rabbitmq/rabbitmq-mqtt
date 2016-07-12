-module(reader_SUITE).
-compile([export_all]).

-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

all() ->
    [
      {group, non_parallel_tests}
    ].

groups() ->
    [
      {non_parallel_tests, [], [
                                block
                               ]}
    ].

suite() ->
    [{timetrap, {seconds, 60}}].

%% -------------------------------------------------------------------
%% Testsuite setup/teardown.
%% -------------------------------------------------------------------

mqtt_config(Config) ->
    P = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_mqtt_extra),
    P2 = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_mqtt_tls_extra),
    {rabbitmq_mqtt, [
       {ssl_cert_login,   true},
       {allow_anonymous,  true},
       {tcp_listeners,    [P]},
       {ssl_listeners,    [P2]}
       ]}.

init_per_suite(Config) ->
    rabbit_ct_helpers:log_environment(),
    Config1 = rabbit_ct_helpers:set_config(Config, [
        {rmq_nodename_suffix, ?MODULE},
        {rmq_extra_tcp_ports, [tcp_port_mqtt_extra,
                               tcp_port_mqtt_tls_extra]}
      ]),
    rabbit_ct_helpers:run_setup_steps(Config1,
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
    rabbit_ct_helpers:testcase_started(Config, Testcase).

end_per_testcase(Testcase, Config) ->
    rabbit_ct_helpers:testcase_finished(Config, Testcase).


%% -------------------------------------------------------------------
%% Testsuite cases
%% -------------------------------------------------------------------

block(Config) ->
    P = rabbit_ct_broker_helpers:get_node_config(Config, 0, tcp_port_mqtt),
    % ok = rpc(Config, ?MODULE, change_configuration, [mqtt_config(Config)]),
    {ok, C} = emqttc:start_link([{host, "localhost"},
                                 {port, P},
                                 {client_id, <<"simpleClient">>},
                                 {proto_ver, 3},
                                 {logger, info},
                                 {puback_timeout, 1}]),
    %% Only here to ensure the connection is really up
    emqttc:subscribe(C, <<"TopicA">>, qos0),
    emqttc:publish(C, <<"TopicA">>, <<"Payload">>),
    expect_publishes(<<"TopicA">>, [<<"Payload">>]),
    emqttc:unsubscribe(C, [<<"TopicA">>]),

    emqttc:subscribe(C, <<"Topic1">>, qos0),

    %% Not blocked
    {ok, _} = emqttc:sync_publish(C, <<"Topic1">>, <<"Not blocked yet">>,
                                  [{qos, 1}]),

    ok = rpc(Config, vm_memory_monitor, set_vm_memory_high_watermark, [0.00000001]),
    ok = rpc(Config, rabbit_alarm, set_alarm, [{{resource_limit, memory, node()}, []}]),

    %% Let it block
    timer:sleep(100),
    %% Blocked, but still will publish
    {error, ack_timeout} = emqttc:sync_publish(C, <<"Topic1">>, <<"Now blocked">>,
                                  [{qos, 1}]),

    %% Blocked
    {error, ack_timeout} = emqttc:sync_publish(C, <<"Topic1">>,
                                               <<"Blocked">>, [{qos, 1}]),

    rpc(Config, vm_memory_monitor, set_vm_memory_high_watermark, [0.4]),
    rpc(Config, rabbit_alarm, clear_alarm, [{resource_limit, memory, node()}]),

    %% Let alarms clear
    timer:sleep(1000),

    expect_publishes(<<"Topic1">>, [<<"Not blocked yet">>,
                                    <<"Now blocked">>,
                                    <<"Blocked">>]),

    emqttc:disconnect(C).

expect_publishes(_Topic, []) -> ok;
expect_publishes(Topic, [Payload|Rest]) ->
    receive
        {publish, Topic, Payload} -> expect_publishes(Topic, Rest)
        after 500 ->
            throw({publish_not_delivered, Payload})
    end.

rpc(Config, M, F, A) ->
    rabbit_ct_broker_helpers:rpc(Config, 0, M, F, A).

change_configuration({App, Args}) ->
    ok = application:stop(App),
    ok = change_cfg(App, Args),
    application:start(App).

change_cfg(_, []) ->
    ok;
change_cfg(App, [{Name,Value}|Rest]) ->
    ok = application:set_env(App, Name, Value),
    change_cfg(App, Rest).

