# encoding: utf-8

require 'cfndsl/JSONable'

module CfnDsl
  class MetadataDefinition < JSONable
    ##
    # Handles Metadata objects
    def initialize(value)
      @value = value
    end

    attr_reader :value

    def to_json(*a)
      @value.to_json(*a)
    end
  end
end
