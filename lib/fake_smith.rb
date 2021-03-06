begin
  require "smith"
  require "smith/agent"
rescue LoadError
end

require "fake_smith/version"
require "delegate"

class FakeSmith
  class ReceiverDecorator < SimpleDelegator
    def ack
      raise MessageAckedTwiceError, "message was acked twice" if @acked
      @acked = true
      super
    end
    alias :call :ack

    def to_proc
      proc { |obj| ack }
    end
  end

  class MessageAckedTwiceError < StandardError; end

  def self.set_reply_handler(queue_name, &blk)
    @reply_handlers ||= {}
    @reply_handlers[queue_name] = blk
  end

  def self.reply_handlers
    @reply_handlers ||= {}
  end

  def self.send_message(queue_name, payload, receiver)
    raise "no subscribers on queue: #{queue_name}" unless subscriptions[queue_name]
    receiver = ReceiverDecorator.new(receiver)
    opts = subscriptions_options[queue_name]
    auto_ack = opts.key?(:auto_ack) ? opts[:auto_ack] : true
    receiver.ack if auto_ack
    subscriptions[queue_name].call(payload, receiver)
  end

  def self.define_subscription(queue_name, options, &blk)
    subscriptions[queue_name] = blk
    subscriptions_options[queue_name] = options
  end

  def self.undefine_subscription(queue_name, &blk)
    subscriptions.delete(queue_name)
    blk.call
  end

  def self.get_messages(queue_name)
    messages[queue_name] ||= []
  end

  def self.add_message(queue_name, message)
    messages[queue_name] ||= []
    messages[queue_name] << message
  end

  def self.clear_all
    clear_subscriptions
    clear_messages
    clear_logger
  end

  def self.subscribed_queues
    subscriptions.keys
  end

  def self.logger
    @logger ||= FakeSmith::Logger.new
  end

  private

  def self.messages
    @messages ||= {}
  end

  def self.clear_messages
    @messages = {}
  end

  def self.subscriptions
    @subscriptions ||= {}
  end

  def self.subscriptions_options
    @subscriptions_options ||= {}
  end

  def self.clear_subscriptions
    @subscriptions = {}
  end

  def self.clear_logger
    @logger = nil
  end

  class Logger
    attr_reader :logs

    def initialize
      @logs = {}
    end

    def log(level)
      @logs[level] ||= []
    end

    [:verbose, :debug, :info, :warn, :error, :fatal].each do |level|
      define_method(level) do |data = nil, &blk|
        if blk
          log(level) << blk.call
        else
          log(level) << data
        end
      end
    end
  end
end

module Smith
  module Messaging
    class Receiver
      def initialize(queue_name, options = {})
        @queue_name = queue_name
        @options = options
      end

      def subscribe(&blk)
        FakeSmith.define_subscription(@queue_name, @options, &blk)
      end

      def unsubscribe(&blk)
        FakeSmith.undefine_subscription(@queue_name, &blk)
      end

      def requeue_parameters(opts)
        @requeue_opts = opts
      end

      def on_requeue_limit(&blk)
        @on_requeue_limit = blk
      end
    end
  end
end

module Smith
  module Messaging
    class Sender
      attr_reader :queue_name

      def initialize(queue_name, _opts = nil, &blk)
        @queue_name = queue_name
        blk.call(self) if block_given?
      end

      def on_reply(_opts, &blk)
        @on_reply = blk
      end

      def on_timeout(&blk)
      end

      def publish(message, &blk)
        FakeSmith.add_message(@queue_name, message)
        blk.call if block_given?
        if FakeSmith.reply_handlers[@queue_name] && @on_reply
          @on_reply.call(FakeSmith.reply_handlers[@queue_name].call(message))
        end
      end

      def message_count(&blk)
        blk.call FakeSmith.get_messages(@queue_name).count if block_given?
      end
    end
  end
end


module Smith
  class Agent

    def initialize
    end

    def self.options(opts)
    end

    def run_signal_handlers(sig, handlers)
    end

    def setup_control_queue
    end

    def setup_stats_queue
    end

    def receiver(queue_name, opts={}, &blk)
      r = Smith::Messaging::Receiver.new(queue_name, opts, &blk)
      blk.call r if block_given?
      r
    end

    def sender(queue_names, opts={}, &blk)
      Array(queue_names).each { |queue_name| Smith::Messaging::Sender.new(queue_name, opts, &blk)  }
    end

    def acknowledge_start(&blk)
      blk.call
    end

    def acknowledge_stop(&blk)
      blk.call
    end

    def start_keep_alive
    end

    def queues
    end

    def logger
      FakeSmith.logger
    end

    def get_test_logger
      logger
    end
  end
end
