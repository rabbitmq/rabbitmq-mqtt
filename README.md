# RabbitMQ MQTT adapter

## Introduction

This is a protocol adapter that allows MQTT-capable clients to
connect to a RabbitMQ broker. The adapter translates MQTT
methods into their AMQP equivalents and back.

## Supported MQTT features

* QoS0 and QoS1 publish & consume
* Last Will and Testament (LWT)
* SSL
* Session stickiness

## Configuration

The main RabbitMQ configuration file also specifies the MQTT
configuration. For details see the [broker configuration documentation](http://www.rabbitmq.com/configure.html).
It is an Erlang-syntax file of the form:

    [{section1, [section1-config]},
     {section2, [section2-config]},
     ...
     {sectionN, [sectionN-config]}
    ].

thus a list of tuples, where the left element of each tuple names the
applications being configured. Don't forget the last element of the
list doesn't have a trailing comma, and don't forget the full-stop is
needed after closing the list. Hence if you configure RabbitMQ-server
and the MQTT adapter, then the configuration file may have a
structure like this:

    [{rabbit,        [configuration-for-RabbitMQ-server]},
     {rabbitmq_mqtt, [configuration-for-RabbitMQ-mqtt-adapter]}
    ].

Here is a sample configuration that sets every MQTT option:

    [{rabbit,        [{tcp_listeners,    [5672]}]},
     {rabbitmq_mqtt, [{default_user,     <<"guest">>},
                      {default_pass,     <<"guest">>},
                      {allow_anonymous,  true},
                      {vhost,            <<"/">>},
                      {default_exchange, <<"amq.topic">>},
                      {exchange_mapping, undefined},
                      {topic_mapping,    undefined},
                      {subscription_ttl, 1800000},
                      {prefetch,         10},
                      {ssl_listeners,    []},
                      {tcp_listeners,    [1883]},
                      {tcp_listen_options, [binary,
                                            {packet,    raw},
                                            {reuseaddr, true},
                                            {backlog,   128},
                                            {nodelay,   true}]}]}
    ].

The `default_user` and `default_pass` options are used to authenticate
the adapter in case MQTT clients provide no login credentials. If the
`allow_anonymous` option is set to `false` then clients MUST provide credentials.
The presence of client-supplied credentials over the network overrides
the `allow_anonymous` option.

The `vhost` option controls which RabbitMQ vhost the adapter connects to and the
`default_exchange` option determines which exchange messages from MQTT clients are
published to by default. If a non-default exchange is chosen then it must be created
before clients publish any messages. The exchange is expected to be an AMQP topic exchange.

The `exchange_mapping` option allows for mapping topics that match a particular regular
expression to a non-default exchange. Mappings are specified by means of a search pattern
and a replace string that are applied to the topic-implied routing key. The resulting string
is then taken as the exchange name. For instance, if you want to map the MQTT topic
`finance/stock/vmware` to the exchange `finance.topic`, and the topic `weather/country/gb` to
the exchange `weather.topic`, you would set `exchange_mapping` option to

```
{<<"^(finance|weather)\\..*)$">>, <<"\\2.topic">>}
```

The first item in the tuple is the search pattern whereas the second item is the replace
string. Refer to the [Erlang regular expression docs](http://www.erlang.org/doc/man/re.html#replace-4)
for more information on valid patterns. Note that the mapping is carried out on the AMQP routing key and
not the MQTT topic. They are almost the same, but not exactly: The MQTT adapter translates topics into routing keys
by replacing `/` with `.` and `+` with `*`.

The `topic_mapping` options is almost identical to the `exchange_mapping` option except that it allows
for rewriting of routing keys using regular expressions. Extending the above finance/weather example, you
could set this option to the following:

 ```
 {<<"^((finance|weather)\\.(.*))$">>, <<"\\3">>}
 ```

Together with the `exchange_mapping` from above this will turn an MQTT topic of `finance/stock/vmware` into
the routing key `stock.vmware` with the exchange `finance.topic`.

While exchange and topic mappings may seem complex at first, they allow for very granular control on how
MQTT is bridged to AMQP.

The `subscription_ttl` option controls the lifetime of non-clean sessions. This
option is interpreted in the same way as the [queue TTL](http://www.rabbitmq.com/ttl.html#queue-ttl)
parameter, so the value `1800000` means 30 minutes.

The `prefetch` option controls the maximum number of unacknowledged messages that
will be delivered. This option is interpreted in the same way as the [AMQP prefetch-count](http://www.rabbitmq.com/amqp-0-9-1-reference.html#basic.qos.prefetch-count)
field, so a value of `0` means "no limit".

The `ssl_listeners` option controls the endpoint (if any) that the adapter accepts
SSL connections on. The default MQTT SSL port is 8883. If this option is non-empty
then the `rabbit` section of the configuration file must contain an `ssl_options`
entry. See the [SSL configuration guide](http://www.rabbitmq.com/ssl.html) for
details.

The `tcp_listeners` and `tcp_listen_options` options are interpreted in the same way
as the corresponding options in the `rabbit` section, as explained in the
[broker configuration documentation](http://www.rabbitmq.com/configure.html).

## AMQP mapping

This is an outline of the mapping between the MQTT and AMQP
methods involved in each of the message flows supported by
the adapter. It is not necessary to know this in order
to use the adapter.

              (MQTT)    ADAPTER    (AMQP)

*    QOS0 flow publish

             PUBLISH   ------>    basic.publish

*    QOS0 flow receive

             PUBLISH   <------    basic.deliver

*    QOS1 flow publish (tracked in state.unacked\_pub)

             PUBLISH   ------>    basic.publish  --+
                                                   |
             PUBACK    <------    basic.ack     <--+

*   QOS1 flow receive (tracked in state.awaiting\_ack)

        +--  PUBLISH   <------    basic.deliver
        |
        +--> PUBACK    ------>    basic.ack
