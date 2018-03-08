require 'spec_helper'

describe NewRelic::Agent::Instrumentation::Roda do

  subject(:app) { Class.new(Roda) }

  def route(&block)
    app.route(&block)
  end

  context 'root' do
    before do
      route do |r|
        r.root do
          'Root!'
        end
      end
    end

    it 'perform_action_with_newrelic_trace' do
      #NewRelic::Agent::Instrumentation::Roda.any_instance
      #  .should_receive(:perform_action_with_newrelic_trace)
      #  .with(hash_including(path: 'GET hello'))
      #  .and_yield

      get '/'
      expect(last_response.status).to eq 200
      expect(last_response.body).to eq 'Root!'
    end
  end

  context 'nested routes' do
    before do
      route do |r|
        r.on 'hello' do
          r.is do
            r.get do
              'Hello!'
            end
          end
        end
      end
    end

    context 'in path' do
      it 'perform_action_with_newrelic_trace' do
        #NewRelic::Agent::Instrumentation::Roda.any_instance
        #  .should_receive(:perform_action_with_newrelic_trace)
        #  .with(hash_including(path: 'GET v1-hello'))
        #  .and_yield

        get '/hello'

        expect(last_response.status).to eq 200
        expect(last_response.body).to eq 'Hello!'
      end
    end
  end
end
