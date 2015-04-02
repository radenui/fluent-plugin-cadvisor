require 'rest-client'
require 'digest/sha1'
require 'time'
require 'docker'

class CadvisorInput < Fluent::Input
  class TimerWatcher < Coolio::TimerWatcher

    def initialize(interval, repeat, log, &callback)
      @callback = callback
      @log = log
      super(interval, repeat)
    end
    def on_timer
      @callback.call
    rescue
      @log.error $!.to_s
      @log.error_backtrace
    end
  end

  Fluent::Plugin.register_input('cadvisor', self)

  config_param :host, :string, :default => 'localhost'
  config_param :port, :string, :default => 8080
  config_param :api_version, :string, :default => '2.0'
  config_param :stats_interval, :time, :default => 60 # every minute
  config_param :tag_prefix, :string, :default => "metric"
  config_param :docker_url, :string,  :default => 'unix:///var/run/docker.sock'

  def initialize
    super
    require 'socket'

    Docker.url = @docker_url
    @hostname = Socket.gethostname
    @dict     = {}
  end

  def configure(conf)
    super
  end

  def start
    @cadvisorEP ||= "http://#{@host}:#{@port}/api/v#{@api_version}"
    @machine    ||= get_spec

    @loop = Coolio::Loop.new
    tw = TimerWatcher.new(@stats_interval, true, @log, &method(:get_metrics))
    tw.attach(@loop)
    @thread = Thread.new(&method(:run))
  end

  def run
    @loop.run
  rescue
    log.error "unexpected error", :error=>$!.to_s
    log.error_backtrace
  end

  def get_interval (current, previous)
    cur  = Time.parse(current).to_f
    prev = Time.parse(previous).to_f

    # to nano seconds
    (cur - prev) * 1000000000
  end

  def get_spec
    response = RestClient.get(@cadvisorEP + "/machine")
    JSON.parse(response.body)
  end

  # Metrics collection methods
  def get_metrics
    Docker::Container.all.each do |obj|
      emit_container_info(obj)
    end
  end

  def emit_container_info(obj)
    container_json = obj.json
    

    id   = container_json['Id']
    name = container_json['Name']
    restart_count = container_json['RestartCount']
    config = container_json['Config']
    image_name = config['Image']
    hostname  = config['Hostname']
    env = hostname.split('--')[2] || '' # app--version--env

    response = RestClient.get(@cadvisorEP + "/containers/docker/" + id)
    res = JSON.parse(response.body)

    # Set max memory
    memory_limit = @machine['memory_capacity'] < res['spec']['memory']['limit'] ? @machine['memory_capacity'] : res['spec']['memory']['limit']

    latest_timestamp = @dict[id] ||= 0

    # Remove already sent elements
    res['stats'].reject! do | stats |
      Time.parse(stats['timestamp']).to_i <= latest_timestamp
    end

    res['stats'].each_with_index do | stats, index |
      timestamp = Time.parse(stats['timestamp']).to_i
      # Break on last element
      # We need 2 elements to create the percentage, in this case the prev will be
      # out of the array
      if index == (res['stats'].count - 1)
        @dict[id] = timestamp
        break
      end

      num_cores = stats['cpu']['usage']['per_cpu_usage'].count

      # CPU percentage variables
      prev           = res['stats'][index + 1];
      raw_usage      = stats['cpu']['usage']['total'] - prev['cpu']['usage']['total']
      interval_in_ns = get_interval(stats['timestamp'], prev['timestamp'])

      record = {
        'id'                 => Digest::SHA1.hexdigest("#{image_name}#{id}#{timestamp.to_s}"),
        'container_id'       => id,
        'image'              => image_name,
        'name'               => name,
        'hostname'           => hostname,
        'environment'        => env,
        'restart_count'      => restart_count,
        'memory_current'     => stats['memory']['usage'],
        'memory_limit'       => memory_limit,
        'cpu_usage'          => raw_usage,
        'cpu_usage_pct'      => (((raw_usage / interval_in_ns ) / num_cores ) * 100).round(2),
        'cpu_num_cores'      => num_cores,
        'cpu_cumulative_total' => stats['cpu']['usage']['total'],
        'cpu_cumulative_user' => stats['cpu']['usage']['user'],
        'cpu_cumulative_sys' => stats['cpu']['usage']['system'],
        'cpu_load_average'   => stats['cpu']['load_average'],
        'network_rx_bytes'   => stats['network']['rx_bytes'],
        'network_rx_packets' => stats['network']['rx_packets'],
        'network_rx_errors'  => stats['network']['rx_errors'],
        'network_rx_dropped' => stats['network']['rx_dropped'],
        'network_tx_bytes'   => stats['network']['tx_bytes'],
        'network_tx_packets' => stats['network']['tx_packets'],
        'network_tx_errors'  => stats['network']['tx_errors'],
        'network_tx_dropped' => stats['network']['tx_dropped'],
      }

      Fluent::Engine.emit("#{tag_prefix}stats", timestamp, record)
    end
  end

  def shutdown
    @loop.stop
    @thread.join
  end
end
