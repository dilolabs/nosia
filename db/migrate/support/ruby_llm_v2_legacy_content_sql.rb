# frozen_string_literal: true

# Frozen from RubyLLM v2.0.0 for historical migration replay:
# https://github.com/crmne/ruby_llm/blob/v2.0.0/lib/generators/ruby_llm/upgrade/legacy_content_sql.rb
#
# MIT License
#
# Copyright (c) 2025 Carmine Paolino
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

module NosiaMigration
  class RubyLlmV2LegacyContentSql
    SPACE = [ 9, 10, 11, 12, 13, 32, 133, 160, 5760, *8192..8202, 8232, 8233, 8239, 8287, 12_288 ].pack("U*").freeze

    def initialize(connection)
      @connection = connection
    end

    def render(content:, raw:)
      normalized, rendered, nonblank = expressions(raw)
      present = "#{normalized} NOT IN ('null', 'false', '[]', '{}') AND #{nonblank}"
      "CASE WHEN #{present} THEN #{rendered} ELSE #{content} END"
    end

    private
      def expressions(raw)
        case @connection.adapter_name
        when "PostgreSQL"
          [ "(#{raw}::jsonb)::text", "#{raw}::text",
            "btrim(#{raw}::jsonb #>> '{}', #{@connection.quote(SPACE)}) <> ''" ]
        when "Mysql2"
          [ "CAST(#{raw} AS CHAR)", "CAST(#{raw} AS CHAR)",
            "JSON_UNQUOTE(#{raw}) NOT REGEXP '^[[:space:]]*$'" ]
        else
          [ "json(#{raw})", raw, "trim(json_extract(#{raw}, '$'), #{@connection.quote(SPACE)}) <> ''" ]
        end
      end
  end
end
