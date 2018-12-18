desc "Log 'foo!'"
task :foo do
  Rails.logger = ActiveSupport::Logger.new(Rails.root.join('log', "#{Rails.env}.log"))
  Rails.logger.info 'foo!'
end
