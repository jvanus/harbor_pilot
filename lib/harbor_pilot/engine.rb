module HarborPilot
  class Engine < ::Rails::Engine
    isolate_namespace HarborPilot

    def engine_file(path)
      HarborPilot::Engine.root.join path
    end

    initializer 'harbor_pilot.configuration' do |app|
      config = HarborPilot.configuration
        app.routes.append do
          mount HarborPilot::Engine => config.route_path
        end
    end
  end
end
