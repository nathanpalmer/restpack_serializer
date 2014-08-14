require 'active_support/concern'
require_relative "options"
require_relative "serializable/attributes"
require_relative "serializable/filterable"
require_relative "serializable/paging"
require_relative "serializable/resource"
require_relative "serializable/single"
require_relative "serializable/side_loading"

module RestPack
  module Serializer
    extend ActiveSupport::Concern
    mattr_accessor :class_map
    @@class_map ||= {}

    included do
      identifier = self.to_s.downcase.chomp('serializer')
      @@class_map[identifier] = self
      @@class_map[identifier.split('::').last] = self
    end

    include RestPack::Serializer::Paging
    include RestPack::Serializer::Resource
    include RestPack::Serializer::Single
    include RestPack::Serializer::Attributes
    include RestPack::Serializer::Filterable
    include RestPack::Serializer::SideLoading

    class InvalidInclude < Exception; end

    def as_json(model, context = {})
      return if model.nil?
      if model.kind_of?(Array)
        return model.map { |item| as_json(item, context) }
      end

      @model, @context = model, context

      data = {}
      if self.class.serializable_attributes.present?
        self.class.serializable_attributes.each do |key, name|
          data[key] = self.send(name) if include_attribute?(name)
        end
      end

      add_custom_attributes(data)
      add_links(model, data)

      data
    end

    def custom_attributes
      {}
    end

    private

    def add_custom_attributes(data)
      custom = custom_attributes
      data.merge!(custom) if custom
    end

    def add_links(model, data)
      self.class.associations.each do |association|
        if association.macro == :belongs_to
          data[:links] ||= {}
          foreign_key_value = model.send(association.foreign_key)
          if foreign_key_value
            data[:links][association.name.to_sym] = foreign_key_value.to_s
          end
        end
      end
      data
    end

    def include_attribute?(name)
      self.send("include_#{name}?".to_sym)
    end

    module ClassMethods
      attr_accessor :model_class, :key

      def array_as_json(models, context = {})
        new.as_json(models, context)
      end

      def as_json(model, context = {})
        new.as_json(model, context)
      end

      def serialize(models, context = {})
        models = [models] unless models.kind_of?(Array)

        {
          self.key() => models.map {|model| self.as_json(model, context)}
        }
      end

      def model_class
        @model_class || self.name.chomp('Serializer').constantize
      end

      def key
        (@key || self.model_class.respond_to?(:table_name)      ? self.model_class.send(:table_name) :
                 self.model_class.respond_to?(:collection_name) ? self.model_class.send(:collection_name) :
                 nil).to_sym
      end

    end
  end
end
