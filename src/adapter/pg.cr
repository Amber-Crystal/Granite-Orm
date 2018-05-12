require "./base"
require "pg"

# PostgreSQL implementation of the Adapter
class Granite::Adapter::Pg < Granite::Adapter::Base
  QUOTING_CHAR = '"'

  module Schema
    TYPES = {
      "AUTO_Int32" => "SERIAL PRIMARY KEY",
      "AUTO_Int64" => "BIGSERIAL PRIMARY KEY",
      "created_at" => "TIMESTAMP",
      "updated_at" => "TIMESTAMP",
    }
  end  

  # remove all rows from a table and reset the counter on the id.
  def clear(table_name)
    statement = "DELETE FROM #{quote(table_name)}"

    log statement

    open do |db|
      db.exec statement
    end
  end

  # select performs a query against a table.  The table_name and fields are
  # configured using the sql_mapping directive in your model.  The clause and
  # params is the query and params that is passed in via .all() method
  def select(table_name, fields, clause = "", params = [] of DB::Any, &block)
    clause = _ensure_clause_template(clause)

    statement = String.build do |stmt|
      stmt << "SELECT "
      stmt << fields.map { |name| "#{quote(table_name)}.#{quote(name)}" }.join(", ")
      stmt << " FROM #{quote(table_name)} #{clause}"
    end

    log statement, params

    open do |db|
      db.query statement, params do |rs|
        yield rs
      end
    end
  end

  # select_one is used by the find method.
  def select_one(table_name, fields, field, id, &block)
    statement = String.build do |stmt|
      stmt << "SELECT "
      stmt << fields.map { |name| "#{quote(table_name)}.#{quote(name)}" }.join(", ")
      stmt << " FROM #{quote(table_name)}"
      stmt << " WHERE #{quote(field)}=$1 LIMIT 1"
    end

    log statement, id

    open do |db|
      db.query_one? statement, id do |rs|
        yield rs
      end
    end
  end

  def insert(table_name, fields, params, lastval)
    statement = String.build do |stmt|
      stmt << "INSERT INTO #{quote(table_name)} ("
      stmt << fields.map { |name| "#{quote(name)}" }.join(", ")
      stmt << ") VALUES ("
      stmt << fields.map { |name| "$#{fields.index(name).not_nil! + 1}" }.join(", ")
      stmt << ")"
    end

    log statement, params

    open do |db|
      db.exec statement, params
      if lastval
        return db.scalar(last_val()).as(Int64)
      else
        return -1_i64
      end
    end
  end

  def import(table_name : String, primary_name : String, fields, model_array, **options)
    params = [] of DB::Any
    now = Time.now.to_utc
    fields.reject! { |field| field === "id" } if primary_name === "id"
    index = 0

    statement = String.build do |stmt|
      stmt << "INSERT"
      stmt << " INTO #{quote(table_name)} ("
      stmt << fields.map { |field| quote(field) }.join(", ")
      stmt << ") VALUES "

      model_array.each do |model|
        model.updated_at = now if model.responds_to? :updated_at
        model.created_at = now if model.responds_to? :created_at
        next unless model.valid?
        stmt << '('
        stmt << fields.map_with_index { |_f, idx| "$#{index + idx + 1}" }.join(',')
        params.concat fields.map { |field| model.to_h[field] }
        stmt << "),"
        index += fields.size
      end
    end.chomp(',')

    if options["update_on_duplicate"]?
      if columns = options["columns"]?
        statement += " ON CONFLICT (#{quote(primary_name)}) DO UPDATE SET "
        columns.each do |key|
          statement += "#{quote(key)}=EXCLUDED.#{quote(key)}, "
        end
      end
      statement = statement.chomp(", ")
    elsif options["ignore_on_duplicate"]?
      statement += " ON CONFLICT DO NOTHING"
    end

    log statement, params

    open do |db|
      db.exec statement, params
    end
  end

  private def last_val
    return "SELECT LASTVAL()"
  end

  # This will update a row in the database.
  def update(table_name, primary_name, fields, params)
    statement = String.build do |stmt|
      stmt << "UPDATE #{quote(table_name)} SET "
      stmt << fields.map { |name| "#{quote(name)}=$#{fields.index(name).not_nil! + 1}" }.join(", ")
      stmt << " WHERE #{quote(primary_name)}=$#{fields.size + 1}"
    end

    log statement, params

    open do |db|
      db.exec statement, params
    end
  end

  # This will delete a row from the database.
  def delete(table_name, primary_name, value)
    statement = "DELETE FROM #{quote(table_name)} WHERE #{quote(primary_name)}=$1"

    log statement, value

    open do |db|
      db.exec statement, value
    end
  end

  private def _ensure_clause_template(clause)
    if clause.includes?("?")
      num_subs = clause.count("?")

      num_subs.times do |i|
        clause = clause.sub("?", "$#{i + 1}")
      end
    end

    clause
  end
end
