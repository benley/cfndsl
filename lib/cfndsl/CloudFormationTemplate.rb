# encoding: utf-8

require 'cfndsl/JSONable'
require 'cfndsl/names'

module CfnDsl
  class OrchestrationTemplate < JSONable
    ##
    # Handles the overall template object
    dsl_attr_setter :AWSTemplateFormatVersion, :Description
    dsl_content_object :Condition, :Parameter, :Output, :Resource, :Mapping
    attr_accessor :Resources

    def initialize
      @AWSTemplateFormatVersion = '2010-09-09'
    end

    @@globalRefs = {
      'AWS::NotificationARNs' => 1,
      'AWS::Region' => 1,
      'AWS::StackId' => 1,
      'AWS::StackName' => 1,
      'AWS::AccountId' => 1,
      'AWS::NoValue' => 1
    }

    def isValidRef(ref, origin = nil)
      ref = ref.to_s
      origin = origin.to_s if origin

      return true if @@globalRefs.key?(ref)

      return true if @Parameters && @Parameters.key?(ref)

      if @Resources.key?(ref)
        return !origin || !@_ResourceRefs || !@_ResourceRefs[ref] || !@_ResourceRefs[ref].key?(origin)
      end

      false
    end

    def checkRefs
      invalids = []
      @_ResourceRefs = {}
      if @Resources
        @Resources.keys.each do |resource|
          @_ResourceRefs[resource.to_s] = @Resources[resource].references({})
        end
        @_ResourceRefs.keys.each do |origin|
          @_ResourceRefs[origin].keys.each do |ref|
            unless isValidRef(ref, origin)
              invalids.push "Invalid Reference: Resource #{origin} refers to #{ref}"
            end
          end
        end
      end
      outputRefs = {}
      if @Outputs
        @Outputs.keys.each do |resource|
          outputRefs[resource.to_s] = @Outputs[resource].references({})
        end
        outputRefs.keys.each do |origin|
          outputRefs[origin].keys.each do |ref|
            unless isValidRef(ref, nil)
              invalids.push "Invalid Reference: Output #{origin} refers to #{ref}"
            end
          end
        end
      end
      invalids.length > 0 ? invalids : nil
    end
  end

  class CloudFormationTemplate < OrchestrationTemplate
    def self.template_types
      CfnDsl::AWSTypes::AWS_Types
    end
    def self.type_module
      CfnDsl::AWSTypes
    end

    names = {}
    nametypes = {}
    self.template_types['Resources'].each_pair do |name, type|
      # Subclass ResourceDefinition and generate property methods
      klass = Class.new(CfnDsl::ResourceDefinition)
      klassname = name.split('::').join('_')
      type_module.const_set(klassname, klass)

      klass.instance_eval do
        define_method(:initialize) do |*values, &block|
          @Type = name
        end
      end

      type['Properties'].each_pair do |pname, ptype|
        if ptype.instance_of?(String)
          create_klass = type_module.const_get(ptype)

          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push create_klass.new if values.length < 1
                @Properties ||= {}
                @Properties[pname] ||= CfnDsl::PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval(&block) if block
                @Properties[pname].value
              end
            end
          end
        else
          # Array version
          sing_name = CfnDsl::Plurals.singularize(pname)
          create_klass = type_module.const_get(ptype[0])
          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push [] if values.length < 1
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval(&block) if block
                @Properties[pname].value
              end
            end

            CfnDsl.methodNames(sing_name) do |method|
              define_method(method) do |value = nil, &block|
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new([])
                value = create_klass.new unless value
                @Properties[pname].value.push value
                value.instance_eval(&block) if block
                value
              end
            end
          end
        end
      end

      parts = name.split '::'
      while parts.length > 0
        abreve_name = parts.join '_'
        if names.key? abreve_name
          # this only happens if there is an ambiguity
          names[abreve_name] = nil
        else
          names[abreve_name] = self.type_module.const_get(klassname)
          CfnDsl::Types.const_set(abreve_name, klass) unless klassname == abreve_name
          nametypes[abreve_name] = name
        end
        parts.shift
      end
    end

    # Define property setter methods for each of the unambiguous type names
    names.each_pair do |typename,type|
      next unless type
      class_eval do
        CfnDsl.methodNames(typename) do |method|
          define_method(method) do |name, *values, &block|
            name = name.to_s
            @Resources ||= {}
            resource = @Resources[name] ||= type.new(*values)
            resource.instance_eval(&block) if block
            resource.instance_variable_set('@Type', nametypes[typename])
            resource
          end
        end
      end
    end
  end

  class HeatTemplate < OrchestrationTemplate
    def self.template_types
      CfnDsl::OSTypes::OS_Types
    end
    def self.type_module
      CfnDsl::OSTypes
    end

    names = {}
    nametypes = {}
    self.template_types['Resources'].each_pair do |name, type|
      # Subclass ResourceDefintion and generate property methods
      klass = Class.new(CfnDsl::ResourceDefinition)
      klassname = name.split('::').join('_')
      type_module.const_set(klassname, klass)
      type['Properties'].each_pair do |pname, ptype|
        if ptype.instance_of?(String)
          create_klass = type_module.const_get(ptype)

          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push create_klass.new if values.length < 1
                @Properties ||= {}
                @Properties[pname] ||= CfnDsl::PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval(&block) if block
                @Properties[pname].value
              end
            end
          end
        else
          # Array version
          sing_name = CfnDsl::Plurals.singularize(pname)
          create_klass = type_module.const_get(ptype[0])
          klass.class_eval do
            CfnDsl.methodNames(pname) do |method|
              define_method(method) do |*values, &block|
                values.push [] if values.length < 1
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new(*values)
                @Properties[pname].value.instance_eval(&block) if block
                @Properties[pname].value
              end
            end

            CfnDsl.methodNames(sing_name) do |method|
              define_method(method) do |value = nil, &block|
                @Properties ||= {}
                @Properties[pname] ||= PropertyDefinition.new([])
                value = create_klass.new unless value
                @Properties[pname].value.push value
                value.instance_eval(&block) if block
                value
              end
            end
          end
        end
      end

      parts = name.split '::'
      while parts.length > 0
        abreve_name = parts.join '_'
        if names.key?(abreve_name)
          # this only happens if there is an ambiguity
          names[abreve_name] = nil
        else
          names[abreve_name] = self.type_module.const_get(klassname)
          nametypes[abreve_name] = name
        end
        parts.shift
      end
    end

    # Define property setter methods for each of the unambiguous type names
    names.each_pair do |typename, type|
      next unless type
      class_eval do
        CfnDsl.methodNames(typename) do |method|
          define_method(method) do |name, *values, &block|
            name = name.to_s
            @Resources ||= {}
            resource = @Resources[name] ||= type.new(*values)
            resource.instance_eval(&block) if block
            resource.instance_variable_set('@Type', nametypes[typename])
            resource
          end
        end
      end
    end
  end
end
