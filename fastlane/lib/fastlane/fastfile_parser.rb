require 'parser'
require 'parser/current'
require 'pp'
require "terminal-table"
module Fastlane
  class FastfileParser
    attr_accessor :original_action

    def to_s
      "REMOVE_IT"
    end

    def lines
      @lines ||= []
    end

    def lanes
      @lanes ||= []
    end

    def actions
      @actions ||= []
    end

    def counters
      errors = lines.select { |key| key[:state] == :error }.length
      deprecations = lines.select { |key| key[:state] == :deprecated }.length
      infos = lines.select { |key| key[:state] == :infos }.length
      { errors: errors, deprecations: deprecations, infos: infos, all: errors + infos + deprecations }
    end

    def data
      { lanes: @lanes,  notices: @lines, actions: @actions }
    end

    def bad_options
      [:use_legacy_build_api]
    end

    def fake_action(*args)
      # Suppress UI output
      out_channel = StringIO.new
      $stdout = out_channel
      $stderr = out_channel

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
        lines << { state: :error, line: @line_number, msg: "'#{@original_action}'  failed with:  `#{ex.message}`" }
      end

      # get bad options
      bad_options.each do |b|
        if args.first[b.to_sym]
          lines << { state: :error, line: @line_number, msg: "do not use this option '#{b.to_sym}'" }
        end
      end

      # get deprecated and sensitive's
      options_avail.each do |o|
        if o.sensitive
          self.class.secrets << args.first[o.key.to_sym].to_s if args.first[o.key.to_sym] && !self.class.secrets.include?(args.first[o.key.to_sym].to_s)
          UI.important("AX - #{@original_action.to_sym}: #{@action_vars.inspect}") if $verbose
          @action_vars.each do |e|
            self.class.secrets << e unless self.class.secrets.include?(e)
          end
        end
        if o.deprecated && args.first[o.key.to_sym]
          lines << { state: :deprecated, line: @line_number, msg: "Use of deprecated option - '#{o.key}' - `#{o.deprecated}`" }
        end

        # reenabled output
        $stdout = STDOUT
        $stderr = STDERR
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
    rescue
      return nil
    end

    def analyze
      recursive_analyze(@ast)
      return make_table
    end

    def wrap_string(s, max)
      chars = []
      dist = 0
      s.chars.each do |c|
        chars << c
        dist += 1
        if c == "\n"
          dist = 0
        elsif dist == max
          dist = 0
          chars << "\n"
        end
      end
      chars = chars[0..-2] if chars.last == "\n"
      chars.join
    end

    def make_table
      #
      table_rows = []
      lines.each do |l|
        status = l[:msg].yellow
        linenr = l[:line].to_s.yellow
        level = l[:state].to_s.yellow
        emoji = "⚠️"
        if l[:state] == :error
          status = l[:msg].red
          level = l[:state].to_s.red
          linenr = l[:line].to_s.red
          emoji = "❌"
        end
        if l[:state] == :info
          emoji = "ℹ️"
        end
        table_rows << [emoji, level, linenr, wrap_string(status, 200)]
      end
      if table_rows.length <= 0
        return nil
      end
      table = Terminal::Table.new title: "Fastfile Validation Result".green, headings: ["#", "State", "Line#", "Notice"], rows: table_rows
      return table
    end

    def find(method_name)
      recursive_search_ast(@ast, method_name)
      return @method_source
    end

    private

    def parse(data)
      Parser::CurrentRuby.parse(data)
    rescue
      return nil
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

    def recursive_analyze(ast)
      if ast.nil?
        UI.error("Parse error")
        return nil
      end
      ast.children.each do |child|
        next unless child.class.to_s == "Parser::AST::Node"

        if (child.type.to_s == "send") and (child.children[0].to_s == "" && child.children[1].to_s == "lane")
          @line_number = child.loc.expression.line
          lane_name = child.children[2].children.first
          lanes << lane_name
          if Fastlane::Actions.action_class_ref(lane_name)
            lines << { state: :error, line: @line_number, msg: "Name of the lane `#{lane_name}` already taken by action `#{lane_name}`" }
          end
        end
        if (child.type.to_s == "send") and (child.children[0].to_s == "" && (Fastlane::Actions.action_class_ref(child.children[1].to_s) || find_alias(child.children[1].to_s)))
          src_code = child.loc.expression.source
          src_code.sub!(child.children[1].to_s, "fake_action")
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
            result = eval(dropper + src_code) # rubocop:disable Lint/Eval
          rescue => ex
            UI.important("PARSE ERROR") if $verbose
            UI.important("Exception: #{ex}") if $verbose
          end
          actions << { action: @original_action, result: result, line: @line_number }
        else
          recursive_analyze(child)
        end
      end
    end
  end
end
