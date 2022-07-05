require 'new_relic/agent/instrumentation'
require 'new_relic/agent/instrumentation/controller_instrumentation'
require 'new_relic/agent/instrumentation/sinatra/transaction_namer'

require 'roda'

module NewRelic
  module Agent
    module Instrumentation
      module Roda
        TransactionNamer = NewRelic::Agent::Instrumentation::Sinatra::TransactionNamer
        module RequestMethods
          include ::NewRelic::Agent::MethodTracer

          MAX_PARSEABLE_SIZE = 3 * 1024

          def match_all(args)
            all = super
            if all
              (env['new_relic.roda'] ||= [nil]) << args
            end
            all
          end
          add_method_tracer :match_all

          def filter_params(param_hash)         
            filtered_params = ENV['FILTERED_PARAMS']&.split(',')
            param_hash.with_indifferent_access.except(*filtered_params)
          end

          def build_params
            rv = nil
            body_pos = body.respond_to?(:pos) ? body.pos : 0
            begin
              if body.size > MAX_PARSEABLE_SIZE
                raise RangeError
              else
                begin
                  if params.empty?
                    rv = params
                  else
                    parsed_body = JSON.parse(params&.first&.join)
                    rv = filter_params(parsed_body)
                  end 
                rescue JSON::ParserError
                  rv = params
                end
              end
            rescue RangeError
              rv = body
              body.seek(body_pos)
            end
            # TODO: filter ze params - we'll need to somehow send these parameters during the gem initialization to be used here

            rv
          end

          def if_match(args)
            instrumented = proc do |*captures|
              @scope.perform_action_with_newrelic_trace(category: :controller, params: build_params) do
                yield(*captures)
              end
            end
            super(args, &instrumented)
          end

          def block_result(result)
            begin
              txn_name = _route_name
              unless txn_name.nil?
                ::NewRelic::Agent::Transaction.set_default_transaction_name(txn_name, :sinatra)
              end
            rescue => e
              ::NewRelic::Agent.logger.warn('Failed during route_eval to set transaction name', e)
            end

            super
          end

          def _route_name
            route_params = env.fetch('new_relic.roda', ['/'])

            route_name = route_params.flat_map do |route_part|
              if route_part.is_a?(Array)
                route_part.map do |inner_part|
                  if inner_part.is_a?(String)
                    inner_part
                  else
                    inner_part.inspect
                  end
                end
              else
                route_part
              end
            end

            "#{request_method} #{route_name.join('/')}"
          end
        end

        module InstanceMethods
          def self.included(base)
            base.include ::NewRelic::Agent::Instrumentation::ControllerInstrumentation
          end

          def call(*args, &block)
            super
          rescue => error
            ::NewRelic::Agent.notice_error(error)
            raise error
          end

          def _route(&block)
            perform_action_with_newrelic_trace(category: :controller,
                                               params: @_request.params) do
              super
            end
          end
        end
      end
    end
  end
end

DependencyDetection.defer do
  @name = :roda

  depends_on do
    defined?(::Roda)
  end

  executes do
    NewRelic::Agent.logger.info 'Installing Roda instrumentation'
    Roda::RodaPlugins.register_plugin(:new_relic, NewRelic::Agent::Instrumentation::Roda)
    Roda.plugin(:new_relic)
  end

  executes do
    NewRelic::Agent::Instrumentation::MiddlewareProxy.class_eval do
      def self.needs_wrapping?(target)
        (
          !target.respond_to?(:_nr_has_middleware_tracing) &&
          !is_sinatra_app?(target) &&
          !target.is_a?(Proc)
        )
      end
    end
  end
end
