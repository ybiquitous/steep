source 'https://rubygems.org'

# Specify your gem's dependencies in steep.gemspec
gemspec

gem "rake"
gem "minitest", "~> 5.21"
gem "minitest-hooks"
group :stackprof, optional: true do
  gem "stackprof"
end
group :memory_profiler, optional: true do
  gem "memory_profiler"
end
gem 'minitest-slow_test'

gem "debug", require: false, platform: :mri
gem "rbs", path: "../rbs"
