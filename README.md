# Fluent::Plugin::Cadvisor

TODO: Write a gem description

## Installation

Add this line to your application's Gemfile:

    gem 'fluent-plugin-cadvisor'

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install fluent-plugin-cadvisor

## Usage

This plugin uses both cAdvisor API and Docker API.

```
<source>
  type cadvisor
  host localhost
  port 8080
  stats_interval 60
  tag_prefix cadvisor
  api_version 1.2
  docker_url unix:///var/run/docker.sock
</source>

<match cadvisorstats>
 type file
  path /output/cadvisor
  time_slice_format %Y%m%d
  time_slice_wait 10m
  time_format %Y%m%dT%H%M%S%z
  compress gzip
  utc
</match>
```

- host: cadvisor host (default=localhost)
- port: cadvisor port (default=8080)
- stats_interval: in seconds (default=60)
- tag_prefix: fluentd tag prefix (default="metric"). Suffix is "stats".
- api_version: cAdvisor API version (default=1.2). Current is 1.3
- docker_url: unix socket for docker API (default=unix:///var/run/docker.sock).

## Contributing

1. Fork it ( `http://github.com/<my-github-username>/fluent-plugin-cadvisor/fork` )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new Pull Request
