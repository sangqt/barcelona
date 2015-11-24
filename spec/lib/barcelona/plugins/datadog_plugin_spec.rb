require 'rails_helper'

module Barcelona
  module Plugins
    describe DatadogPlugin do
      context "without proxy plugin" do
        let!(:district) do
          create :district, plugins_attributes: [
                   {
                     name: 'datadog',
                     plugin_attributes: {
                       "api_key" => "abcdef"
                     }
                   }
                 ]
        end

        it "gets hooked with container_instance_user_data trigger" do
          section = district.sections[:private]
          ci = ContainerInstance.new(section, instance_type: 't2.micro')
          user_data = YAML.load(Base64.decode64(ci.instance_user_data))
          expect(user_data["runcmd"].last).to eq "docker run -d --name dd-agent -h `hostname` -v /var/run/docker.sock:/var/run/docker.sock -v /proc/:/host/proc/:ro -v /sys/fs/cgroup/:/host/sys/fs/cgroup:ro -e API_KEY=abcdef -e TAGS=\"barcelona,district:#{district.name}\" datadog/docker-dd-agent:latest"
        end
      end

      context "with proxy plugin" do
        let!(:district) do
          create :district, plugins_attributes: [
                   {
                     name: "proxy",
                   },
                   {
                     name: 'datadog',
                     plugin_attributes: {
                       "api_key" => "abcdef"
                     }
                   }
                 ]
        end

        it "gets hooked with container_instance_user_data trigger" do
          section = district.sections[:private]
          ci = ContainerInstance.new(section, instance_type: 't2.micro')
          user_data = YAML.load(Base64.decode64(ci.instance_user_data))
          expect(user_data["runcmd"].last).to include "-e PROXY_HOST=main.#{district.name}-proxy.bcn"
          expect(user_data["runcmd"].last).to include "-e PROXY_PORT=3128"
        end
      end
    end
  end
end