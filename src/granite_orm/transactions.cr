module Granite::ORM::Transactions
  macro __process_transactions
    {% primary_name = PRIMARY[:name] %}
    {% primary_type = PRIMARY[:type] %}

    @updated_at : Time?
    @created_at : Time?

    # The save method will check to see if the primary exists yet. If it does it
    # will call the update method, otherwise it will call the create method.
    # This will update the timestamps apropriately.
    def save
      return false unless valid?

      begin
        __run_before_save
        now = Time.now.to_utc

        if (value = @{{primary_name}}) && !new_record?
          __run_before_update
          @updated_at = now
          params_and_pk = params
          params_and_pk << value
          begin
            @@adapter.update @@table_name, @@primary_name, self.class.fields, params_and_pk
          rescue err
            raise DB::Error.new(err.message)
          end
          __run_after_update
        else
          __run_before_create
          @created_at = @updated_at = now
          params = params()
          fields = self.class.fields
          if value = @{{primary_name}}
            fields << "{{primary_name}}"
            params << value
          end
          begin
            {% if primary_type.id == "Int32" %}
              @{{primary_name}} = @@adapter.insert(@@table_name, fields, params).to_i32
            {% else %}
              @{{primary_name}} = @@adapter.insert(@@table_name, fields, params)
            {% end %}
          rescue err
            raise DB::Error.new(err.message)
          end
          __run_after_create
        end
        @new_record = false
        __run_after_save
        return true
      rescue ex : DB::Error
        if message = ex.message
          Granite::ORM.settings.logger.error "Save Exception: #{message}"
          errors << Granite::ORM::Error.new(:base, message)
        end
        return false
      end
    end

    # Destroy will remove this from the database.
    def destroy
      begin
        __run_before_destroy
        @@adapter.delete(@@table_name, @@primary_name, {{primary_name}})
        __run_after_destroy
        @destroyed = true
        return true
      rescue ex : DB::Error
        if message = ex.message
          Granite::ORM.settings.logger.error "Destroy Exception: #{message}"
          errors << Granite::ORM::Error.new(:base, message)
        end
        return false
      end
    end
  end

  def create(**args)
    create(args.to_h)
  end

  def create(args : Hash(Symbol | String, DB::Any))
    instance = new
    instance.set_attributes(args)
    instance.save
    instance
  end

  # Returns true if this object hasn't been saved yet.
  getter? new_record : Bool = true

  # Returns true if this object has been destroyed.
  getter? destroyed : Bool = false

  # Returns true if the record is persisted.
  def persisted?
    !(new_record? || destroyed?)
  end
end
