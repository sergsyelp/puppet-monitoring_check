module Puppet::Parser::Functions
  newfunction(
    :where,
    :type => :rvalue,
    :doc => <<-'ENDHEREDOC') do |args|
Returns which file called this function so you can debug monitoring checks
ENDHEREDOC
    caller [0][/[^:]+/]
  end
end
