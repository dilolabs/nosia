Rails.application.routes.draw do
  root "static#index"

  resource :first_run

  # Authentication routes
  resources :users, only: [ :create ]
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  # API routes
  get "v1/models", to: "api/v1/models#index"
  post "v1/chat/completions", to: "api/v1/completions#create"
  post "v1/completions", to: "api/v1/completions#create"
  namespace :api do
    namespace :v1 do
      resources :completions, only: [ :create ]
      resources :files, only: [ :create ]
      resources :qnas, only: [ :create ]
      resources :texts, only: [ :create ]
      resources :websites, only: [ :create ]
    end
  end

  # User routes
  constraints Authentication::Authenticated do
    resources :accounts, only: [ :index, :edit, :update ]
    resources :api_tokens, only: [ :index, :create, :destroy ]
    resources :chats, only: [ :show, :new, :create, :destroy ] do
      resources :messages, only: [ :create ]
    end
    resources :chunks, only: [ :show ]
    resources :dashboards, only: [ :show ]
    resources :models, only: [ :index, :show ] do
      collection do
        post :refresh
      end
    end
    resource :settings, only: [ :show ]
    resources :sources, only: [ :index ]
    namespace :sources do
      resources :documents
      resources :qnas
      resources :texts
      resources :websites
    end

    root to: "dashboards#show", as: :user_root
  end

  # Admin routes
  constraints Authentication::Admin do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/*
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
end
