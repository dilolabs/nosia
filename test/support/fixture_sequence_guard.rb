module FixtureSequenceGuard
  private
    def preserve_fixture_sequence(model)
      model.with_connection do |connection|
        return yield unless connection.respond_to?(:set_pk_sequence!)

        model.uncached do
          table = model.table_name
          sequence = connection.quote_table_name(connection.default_sequence_name(table, model.primary_key))
          last_value = "SELECT last_value FROM #{sequence}"
          high_water = [ connection.select_value(last_value), model.unscoped.maximum(:id) ].compact.max
          begin
            yield
          ensure
            # Fixtures replace rows in a transaction, but PostgreSQL's
            # sequence reset survives rollback. Do not reuse IDs it restores.
            if connection.select_value(last_value) < high_water
              connection.set_pk_sequence!(table, high_water)
            end
          end
        end
      end
    end
end
