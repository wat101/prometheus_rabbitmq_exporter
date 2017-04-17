-module(prometheus_rabbitmq_overview_collector).
-export([register/0,
         register/1,
         deregister_cleanup/1,
         collect_mf/2,
         collect_metrics/2]).

-import(prometheus_model_helpers, [create_mf/5,
                                   label_pairs/1,
                                   gauge_metrics/1,
                                   gauge_metric/1,
                                   gauge_metric/2,
                                   counter_metric/1,
                                   counter_metric/2]).

-include("prometheus_rabbitmq_exporter.hrl").
-behaviour(prometheus_collector).

-define(METRIC_NAME_PREFIX, "rabbitmq_").
-define(METRIC_NAME(S), ?METRIC_NAME_PREFIX ++ atom_to_list(S)).

%%====================================================================
%% Collector API
%%====================================================================

register() ->
  register(default).

register(Registry) ->
  ok = prometheus_registry:register_collector(Registry, ?MODULE).

deregister_cleanup(_) -> ok.

collect_mf(_Registry, Callback) ->
  Callback(create_gauge(rabbitmq_connections, "RabbitMQ Connections count", [])),
  Callback(create_gauge(rabbitmq_channels, "RabbitMQ Channels count", [])),
  Callback(create_gauge(rabbitmq_queues, "RabbitMQ Queues count", [])),
  Callback(create_gauge(rabbitmq_exchanges, "RabbitMQ Exchanges count", [])),
  Callback(create_gauge(rabbitmq_consumers, "RabbitMQ Consumers count", [])),


  Overview = rabbit_mgmt_db:get_overview(all, ?NO_RANGE),

  collect_messages_stat(Callback, proplists:get_value(message_stats, Overview)),
  ok.

collect_metrics(_, {messages_stat, MSKey, Stats}) ->
  counter_metric([], proplists:get_value(MSKey, Stats));
collect_metrics(rabbitmq_connections, _MFData) ->
  AllConnections = created_events(connection_stats),
  AllVHosts = rabbit_vhost:info_all([name]),
  [gauge_metric([{vhost, VHost}], length(filter_by_vhost(VHost, AllConnections))) || [{name, VHost}] <- AllVHosts];
collect_metrics(rabbitmq_channels, _MFData) ->
  AllChannels = created_events(channel_stats),
  AllVHosts = rabbit_vhost:info_all([name]),
  [gauge_metric([{vhost, VHost}], length(filter_by_vhost(VHost, AllChannels))) || [{name, VHost}] <- AllVHosts];
collect_metrics(rabbitmq_queues, _MFData) ->
  AllVHosts = rabbit_vhost:info_all([name]),
  [gauge_metric([{vhost, VHost}], length(rabbit_amqqueue:list(VHost))) || [{name, VHost}] <- AllVHosts];
collect_metrics(rabbitmq_exchanges, _MFData) ->
  AllVHosts = rabbit_vhost:info_all([name]),
  [gauge_metric([{vhost, VHost}], length(rabbit_exchange:list(VHost))) || [{name, VHost}] <- AllVHosts];
collect_metrics(rabbitmq_consumers, _MFData) ->
  gauge_metric([], ets:info(consumers_by_queue, size)).

%%====================================================================
%% Private Parts
%%====================================================================

collect_messages_stat(Callback, Stats) ->
  [Callback(create_counter(?METRIC_NAME(MetricName), Help, {messages_stat, MSKey, Stats}))
   || {MSKey, MetricName, Help} <- prometheus_rabbitmq_message_stats:metrics()].


filter_by_vhost(VHost, Channels) ->
  [I || I <- Channels, rabbit_misc:pget(vhost, I) =:= VHost].

%% created_events(Type) ->
%%   ets:select(Type, [{{{'_', '$1'}, '$2', '_'}, [{'==', 'create', '$1'}],
%%                      ['$2']}]).

created_events(connection_stats) ->
  rabbit_mgmt_db:get_all_connections(?NO_RANGE);
created_events(channel_stats) ->
  rabbit_mgmt_db:get_all_channels(?NO_RANGE).

create_gauge(Name, Help, Data) ->
  create_mf(Name, Help, gauge, ?MODULE, Data).

create_counter(Name, Help, Data) ->
  create_mf(Name, Help, counter, ?MODULE, Data).
