module FastlaneCore
  class PrintTable
    class << self
      # This method prints out all the user inputs in a nice table. Useful to summarize the run
      # You can pass an array to `hide_keys` if you don't want certain elements to show up (symbols or strings)
      # You can pass an array to `mask_keys` if you want to mask certain elements (symbols or strings)
      def print_values(config: nil, title: nil, hide_keys: [], mask_keys: [], truncate: true)
        require 'terminal-table'

        options = {}
        unless config.nil?
          if config.kind_of?(FastlaneCore::Configuration)
            options = config.values(ask: false)
          else
            options = config
          end
        end
        rows = self.collect_rows(options: options, hide_keys: hide_keys.map(&:to_s), mask_keys: mask_keys.map(&:to_s), prefix: '')

        params = {}
        truncate = false if Helper.is_ci? || FastlaneCore::Env.truthy?("DO_NOT_TRUNCATE_TABLES")
        params[:rows] = rows unless truncate
        params[:rows] = limit_row_size(rows, truncate) if truncate

        params[:title] = title.green if title

        puts ""
        puts Terminal::Table.new(params)
        puts ""

        return params
      end

      def limit_row_size(rows, max_length = 100)
        require 'fastlane_core/string_filters'
        require 'io/console'

        tcols = IO.console.winsize[1]
        max_length = tcols

        max_key_length = rows.map { |e| e[0].length }.max || 0
        if max_key_length > (max_length / 2) - 6
          max_key_length = (max_length / 2) - 6
        end
        max_allowed_value_length = max_length - max_key_length - 12
        rows.map do |e|
          value = e[1]
          value = value.to_s.middle_truncate(max_allowed_value_length) unless [true, false].include?(value)
          [e[0].to_s.middle_truncate(max_key_length), value]
        end
      end

      def collect_rows(options: nil, hide_keys: [], mask_keys: [], prefix: '', mask: '********')
        rows = []

        options.each do |key, value|
          prefixed_key = "#{prefix}#{key}"
          next if value.nil?
          next if value.to_s == ""
          next if hide_keys.include?(prefixed_key)
          value = mask if mask_keys.include?(prefixed_key)

          if value.respond_to? :key
            rows.concat self.collect_rows(options: value, hide_keys: hide_keys, mask_keys: mask_keys, prefix: "#{prefix}#{key}.", mask: mask)
          else
            rows << [prefixed_key, value]
          end
        end
        rows
      end
    end
  end
end
