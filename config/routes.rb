HarborPilot::Engine.routes.draw do
  get '/healthcheck', to: "healthchecks#status", as: "healthcheck"
end
