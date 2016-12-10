require 'parser'
require 'parser/current'
require 'pp'
module Fastlane
  class FastfileParser
    attr_accessor :original_action

    def to_s
      "REMOVE_IT"
    end

    def fake_action(*args)
      return_data = { args: args.first }
      return return_data if args.length <= 0
      return return_data if @original_action.nil?
      UI.important("ACTION: #{@original_action.inspect} 1") if $verbose
      UI.important("PARAMS: #{args.inspect}") if $verbose
      a = Fastlane::Actions.action_class_ref(@original_action.to_sym)
      a = find_alias(@original_action.to_sym) unless a
      return return_data unless a
      options_avail = a.available_options
      return return_data if options_avail.nil?

      # Validate Options
      begin
        config = FastlaneCore::Configuration.new(options_avail, args.first)
        return_data[:configuration] = config
      rescue => ex
        return_data[:error] = ex.message
      end

      options_avail.each do |o|
        next return_data unless o.sensitive
        self.class.secrets << args.first[o.key.to_sym].to_s if args.first[o.key.to_sym] && !self.class.secrets.include?(args.first[o.key.to_sym].to_s)
        UI.important("AX - #{@original_action.to_sym}: #{@action_vars.inspect}") if $verbose
        @action_vars.each do |e|
          self.class.secrets << e unless self.class.secrets.include?(e)
        end
      end
      return_data
    end

    def self.secrets
      unless @secrets
        @secrets = []
      end
      @secrets
    end

    def dummy
      FastlaneCore::FastfileParser.new("")
    end

    def method_missing(sym, *args, &block)
      UI.important("CHECK #{sym} - #{args.inspect} - #{block.inspect}") if $verbose
      return "dummy" if sym.to_s == "to_str"
      dummy
    end

    def initialize(filename)
      @ast = parse(filename)
    rescue => ex
      return nil
    end

    def parse_it
      actions = find_actions
    end

    def find_actions
      actions = recursive_find_actions(@ast)
      { actions: actions }
    end

    def find(method_name)
      recursive_search_ast(@ast, method_name)
      return @method_source
    end

    private

    def parse(data)
    begin
      Parser::CurrentRuby.parse(data)
    rescue => ex
      return nil
    end
    end

    # from runner.rb -> should be in FastlaneCore or somewhere shared
    def find_alias(action_name)
      Actions.alias_actions.each do |key, v|
        next unless Actions.alias_actions[key]
        next unless Actions.alias_actions[key].include?(action_name)
        return key
      end
      nil
    end

    def recursive_find_actions(ast)
      collected = []
      if ast.nil?
        UI.error("Parse error")
        return nil
      end
      ast.children.each do |child|
        next unless child.class.to_s == "Parser::AST::Node"

        if (child.type.to_s == "send") and (child.children[0].to_s == "" && (Fastlane::Actions.action_class_ref(child.children[1].to_s) || find_alias(child.children[1].to_s)))
          src_code = child.loc.expression.source
          src_code.gsub!(child.children[1].to_s, "fake_action")
          @line_number =  child.loc.expression.line

          # matches = src_code.gsub!(/#\{.*\}/) do |sym|
          #  self.class.secrets << sym if !self.class.secrets.include?(sym)
          #  "########"
          # end
          copy_code = src_code.clone
          @action_vars = []
          src_code.scan(/#\{.*?\}/m) do |mtch|
            # Remove #{} vars - so that there are now accidentalliy replaced ones
            @action_vars << mtch unless self.class.secrets.include?(mtch)
            # copy_code.gsub!(mtch.first, "'#######'")
          end
          src_code = copy_code
          @original_action = child.children[1].to_s
          dropper = '

          '
          UI.important(src_code) if $verbose
          begin
            result = eval(dropper + src_code)
          rescue => ex
            UI.important("PARSE ERROR") if $verbose
            UI.important("Exception: #{ex}") if $verbose
          end
          collected << { action: @original_action, result: result, line: @line_number }
        else
          collected += recursive_find_actions(child)
        end
      end
      return collected
      end
  end
end
