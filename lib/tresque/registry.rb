require 'resque-bus'

module TResque
  class Registry
    class << self
      def default_weight
        100
      end
      
      def class_hash
        @class_hash ||= {}
      end
      
      def queue_hash
        @queue_hash ||= {}
      end
      
      def class_list
        class_hash.keys
      end
      
      def worker(klass)
        klass = klass.name if klass.is_a?(Class)
        klass = klass.to_s
        class_hash[klass] = 1
      end
      
      def queue(queue_name, weight=nil)
        queue_name = queue_name.to_s
        if weight
          # take higher weight
          if !queue_hash[queue_name] || weight > queue_hash[queue_name]
            queue_hash[queue_name] = weight
          end
        else
          queue_hash[queue_name] ||= false
        end
      end

      def weight(key)
        if !self.queue_hash[key]
          self.default_weight
        else
          self.queue_hash[key]
        end
      end
      
      # called to know what queues to set
      def queues
        register_classes
        register_bus
        sorted_queues
      end
      
      protected
      
      def register_classes
        class_list.each do |klass_name|
          klass = klass_name.constantize
          queue(klass.queue)
        end
      end
      
      def register_bus
        manager = QueueBus::TaskManager.new(false)
        manager.queue_names.each do |name|
          queue(name)
        end
        queue("bus_incoming", 1)
      end
      
      def sorted_queues
        array = queue_hash.keys.clone.shuffle
        hash = {}
        array.each do |key|
          hash[key] = self.weight(key)
        end
        # sorted with highest weight first
        array.sort!{ |x,y| hash[y] <=> hash[x] }
        array
      end
    end
    
    attr_reader :app_key
    def initialize(app_key)
      @app_key = Util.normalize(app_key)
    end
    
    def queue(name, weight=nil)
      queue_name = "#{app_key}_#{name}"
      ::TResque::Registry.queue(queue_name, weight)
    end
  end
end