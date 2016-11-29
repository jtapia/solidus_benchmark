
require './dummy/config/environment'
require 'spree/testing_support/factories'
require 'database_cleaner'

DatabaseCleaner.strategy = :truncation
DatabaseCleaner.clean

class SolidusBenchmark
  class Stddev
    def initialize(samples)
      @samples = samples
    end

    def mean
      @mean ||= @samples.inject(:+) / @samples.length
    end

    def variance
      @samples.map do |sample|
        v = (sample - mean)
        v * v
      end.inject(:+) / @samples.length
    end

    def stddev
      @stddev ||= Math.sqrt(variance)
    end
  end

  class Instance
  end

  def initialize(label, &block)
    @label = label
    @setup = @before = @measure = ->{}

    instance_exec(self, &block)

    run!
  end

  # Specify a block that will be run once to pre-populate the database
  def setup(&block)
    @setup = block
  end

  # Specify a block which will be run before each measured block.
  # This will be run multiple times, both for warmup and pre-measurement.
  def before(&block)
    @before = block
  end

  # The block of code to be measured.
  # This will be run multiple times, both for warmup and measurement.
  def measure(&block)
    @measure = block
  end

  def measure_once
    run = @instance.dup
    run.instance_exec(&@before)

    Benchmark.realtime do
      run.instance_exec(&@measure)
    end
  end

  def measure_for(timeout, samples)
    measurements = []
    while measurements.length < samples && measurements.inject(0, :+) < timeout
      measurements << measure_once
    end
    measurements
  end

  def run!
    DatabaseCleaner.start

    @instance = Object.new
    @instance.instance_exec(&@setup)

    # Warmup
    measure_once

    # Take real measurements
    measurements = measure_for(2, 10)

    DatabaseCleaner.clean

    gemspec = Gem::Specification.find_by_name("solidus")
    version = gemspec.version.to_s

    stats = Stddev.new(measurements)
    output = {
      label: @label,
      solidus_version: version,
      database: ActiveRecord::Base.connection.adapter_name,
      mean: stats.mean,
      stddev: stats.stddev
    }.to_json

    puts output
  end
end

