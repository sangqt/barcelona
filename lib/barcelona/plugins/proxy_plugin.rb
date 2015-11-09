module Barcelona
  module Plugins
    class ProxyPlugin < Base
      PROXY_URL = "http://main.proxy.bcn:3128"
      DEFAULT_NO_PROXY = [
        "localhost",
        "127.0.0.1",
        "169.254.169.254",
        ".bcn"
      ]

      def on_container_instance_user_data(instance, user_data)
        return config if instance.section.public?

        user_data.add_file("/etc/profile.d/http_proxy.sh", "root:root", "755", <<EOS)
#!/bin/bash
export http_proxy=#{PROXY_URL}
export https_proxy=#{PROXY_URL}
export no_proxy=#{no_proxy.join(',')}
EOS
        user_data
      end

      def on_heritage_task_definition(heritage, task_definition)
        return task_definition if heritage.name == proxy_heritage_name
        task_definition[:environment] += [
          {name: "http_proxy", value: PROXY_URL},
          {name: "https_proxy", value: PROXY_URL},
          {name: "no_proxy", value: no_proxy.join(',')}
        ]
        task_definition
      end

      def on_ecs_config(instance, config)
        return config if instance.section.public?

        config.merge(
          "HTTP_PROXY" => PROXY_URL,
          "HTTPS_PROXY" => PROXY_URL,
          # Directly connect to metadata service and docker socket
          "NO_PROXY" => "169.254.169.254,/var/run/docker.sock"
        )
      end

      def on_created(_, _)
        params = {
          name: proxy_heritage_name,
          image_name: "k2nr/squid",
          section_name: "public",
          services: [
            {
              name: "main",
              cpu: 256,
              memory: 256,
              port_mappings: [
                {lb_port: 3128, container_port: 3128}
              ]
            }
          ]
        }
        proxy_heritage = BuildHeritage.new(params, district: district).execute
        proxy_heritage.save_and_deploy!
      end

      def on_destroyed(_, _)
        heritage = district.heritages.find_by(name: proxy_heritage_name)
        heritage.destroy!
      end

      private

      def district
        model.district
      end

      def proxy_heritage_name
        "#{district.name}-proxy"
      end

      def no_proxy
        @no_proxy ||= (model.plugin_attributes["no_proxy"] || []).concat(DEFAULT_NO_PROXY)
      end
    end
  end
end