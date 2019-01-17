class HealthchecksController < ActionController::Base

  def status
    render plain: "VERSION: #{HarborPilot.configuration.version}", status: 200
  end

end