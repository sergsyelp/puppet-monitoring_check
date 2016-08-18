require 'spec_helper'

describe 'monitoring_check' do

  context 'without teams data' do
    let(:pre_condition) { %q{
      include apt
      include sensu
    } }
    let(:title) { 'examplecheck' }
    let(:hiera_data) {{ :'sensu_handlers::teams' => { } }}
    let(:facts) { { :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }

    let(:default_interval) { 60 }
    let(:params) { {:command => 'bar', :runbook => 'http://gronk', :page => true} }
      it do
        expect {
          should contain_sensu__check('examplecheck')
        }.to raise_error(Puppet::Error, /No sensu_handlers::teams/)
      end
  end
  context 'with teams data' do
    let(:pre_condition) { %q{
      include apt
      include sensu
    } }
    let(:title) { 'examplecheck' }
    let(:hiera_data) {{ :'sensu_handlers::teams' => { 'operations' => {}, 'other' => {}} }}
    let(:facts) { { :habitat => 'somehabitat', :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }

    let(:default_interval) { 60 }

    context "basic test" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :page => true} }
      it do
        should contain_sensu__check('examplecheck') \
          .with_ensure('present') \
          .with_handlers('default') \
          .with_interval(default_interval) \
          .without_subdue \
          .without_env_vars \
          .with_command('bar') \
          .with_custom({
            "alert_after"        => "0",
            "realert_every"      => "-1",
            "runbook"            => "http://gronk",
            "sla"                => "No SLA defined.",
            "team"               => "operations",
            "irc_channels"       => :undef,
            "notification_email" => "undef",
            "ticket"             => false,
            "project"            => false,
            "page"               => true,
            "tip"                => false,
            "habitat"            => "somehabitat",
            "tags"               => [],
          })
      end
      it { should contain_file('/etc/sensu/team_data.json').with_content(/other/) }
      it { should contain_file('/etc/sensu/team_data.json').with_content(/operations/) }
    end

    context "no handlers" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :handlers => []} }
      it do
        should contain_sensu__check('examplecheck').with_handlers([])
      end
    end

    context 'with non-empty handlers overrides' do
      let(:params) {{ :command => 'foo', :runbook => 'http://gronk' }}
      let(:hiera_data) {{
        'sensu_handlers::teams' => { 'operations' => { } },
        'monitoring_check::handlers' => ['bar','baz']
      }}
      it {
        should contain_sensu__check('examplecheck').with_handlers(['bar','baz'])
      }
    end

    context 'with empty handlers overrides' do
      let(:params) {{ :command => 'foo', :runbook => 'http://gronk' }}
      let(:hiera_data) {{
        'sensu_handlers::teams' => { 'operations' => { } },
        'monitoring_check::handlers' => []
      }}
      it {
        should contain_sensu__check('examplecheck').with_handlers([])
      }
    end

    context 'with check-specific handlers overrides' do
      let(:params) {{ :command => 'foo', :runbook => 'http://gronk' }}
      let(:hiera_data) {{
        'sensu_handlers::teams' => { 'operations' => { } },
        'monitoring_check::handlers' => ['foo'],
        'monitoring_check::handlers::examplecheck' => ['qux'],
      }}
      it {
        should contain_sensu__check('examplecheck').with_handlers(['qux'])
      }
    end

    context "bad runbook (not a uri)" do
      let(:params) { {:command => 'bar', :runbook => 'gronk'} }
      it do
        expect { should contain_monitoring_check('examplecheck') }.to raise_error(Exception, /does not match/)
      end
    end

    context "custom team" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :team => 'other'} }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "other",
        "notification_email" => "undef",
        "habitat"            => "somehabitat",
        "tags"               => [],
      })
      }
    end

    context "custom team (nonexistent)" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :team => 'doesnotexist'} }
      it do
        expect { should contain_monitoring_check('examplecheck') }.to raise_error(Exception, /does not match/)
      end
    end
    context "with one dependency" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :dependencies => 'dep1'} }
      it { should contain_sensu__check('examplecheck').with_dependencies(['dep1']) }
    end

    context "with custom" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :sensu_custom => { 'foo' => 'bar' } } }
      it { should contain_sensu__check('examplecheck').with_custom({
          "runbook"            => "http://gronk",
          "ticket"             => false,
          "irc_channels"       => :undef,
          "tip"                => false,
          "project"            => false,
          "alert_after"        => "0",
          "foo"                => "bar",
          "page"               => false,
          "realert_every"      => "-1",
          "sla"                => "No SLA defined.",
          "team"               => "operations",
          "notification_email" => "undef",
          "habitat"            => "somehabitat",
          "tags"               => [],
        }
      )}
    end

    context "with custom - overriding" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :sensu_custom => { 'team' => 'overridden' } } }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "overridden",
        "notification_email" => "undef",
        "habitat"            => "somehabitat",
        "tags"               => [],
        }
      )}
    end

    context "nowake, nopage" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :page => 'false'} }
      it { should contain_sensu__check('examplecheck').with_custom({
          "runbook"            => "http://gronk",
          "ticket"             => false,
          "irc_channels"       => :undef,
          "tip"                => false,
          "project"            => false,
          "alert_after"        => "0",
          "page"               => false,
          "realert_every"      => "-1",
          "sla"                => "No SLA defined.",
          "team"               => "operations",
          "notification_email" => "undef",
          "habitat"            => "somehabitat",
          "tags"               => [],
        }
      )}
    end

    context "With a SLA defined" do
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :page => 'false', :sla=>'custom SLA'} }
      it { should contain_sensu__check('examplecheck').with_custom({
          "runbook"            => "http://gronk",
          "ticket"             => false,
          "irc_channels"       => :undef,
          "tip"                => false,
          "project"            => false,
          "alert_after"        => "0",
          "page"               => false,
          "realert_every"      => "-1",
          "sla"                => "custom SLA",
          "team"               => "operations",
          "notification_email" => "undef",
          "habitat"            => "somehabitat",
          "tags"               => [],
        }
      )}
    end

    context "sudo" do
      let(:params) { {:command => '/bin/bar --foo --baz', :runbook => 'http://gronk', :needs_sudo => true, :sudo_user => 'fred'} }
      it do
        should contain_sensu__check('examplecheck') \
          .with_command('sudo -H -u fred -- /bin/bar --foo --baz')
        should contain_sudo__conf("sensu_examplecheck") \
          .with_content("sensu       ALL=(fred) NOPASSWD: /bin/bar\nDefaults!/bin/bar !requiretty")
      end
    end
    context "sudo with a non qualified command" do
      let(:params) { {:command => 'bar --foo --baz', :runbook => 'http://gronk', :needs_sudo => true, :sudo_user => 'fred'} }
      it { should_not compile }
    end

    context "check with timeout" do
      let(:params) { { :command => 'bar', :runbook => 'y/gronk', :check_every => '5m', :timeout => 50 } }
      it { should contain_sensu__check('examplecheck').with_timeout(50) }
    end

    context "check default timeout" do
      let(:params) { { :command => 'bar', :runbook => 'y/gronk', :check_every => '5m' } }
      it { should contain_sensu__check('examplecheck').with_timeout(300) }
    end

    context "check default timeout for long period checks" do
      let(:params) { { :command => 'bar', :runbook => 'y/gronk', :check_every => '5h' } }
      it { should contain_sensu__check('examplecheck').with_timeout(3600) }
    end

    context "with override_sensu_checks_to set and can_override true" do
      let(:facts) { { :habitat => "somehabitat", :override_sensu_checks_to => 'custom@override', :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => 'bar', :runbook => 'http://gronk' } }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "noop",
        "notification_email" => "custom@override",
        "habitat"            => "somehabitat",
        "tags"               => [],
        }
      )}
    end
    context "with override_sensu_checks_to set and can_override false" do
      let(:facts) { { :habitat => "somehabitat", :override_sensu_checks_to => 'custom@override', :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :can_override => false } }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "operations",
        "notification_email" => "undef",
        "habitat"            => "somehabitat",
        "tags"               => [],
        }
      )}
    end
    context "with a source" do
      let(:facts) { { :habitat => "somehabitat", :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :source => 'mysource' } }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "operations",
        "notification_email" => "undef",
        "habitat"            => "somehabitat",
        "tags"               => [],
        }
      ).with_source('mysource') }
    end
    context "with a source which has a space" do
      let(:facts) { { :habitat => "somehabitat", :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :source => 'my source' } }
      it { should_not compile }
    end
    context "with tags" do
      let(:facts) { { :habitat => "somehabitat", :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => 'bar', :runbook => 'http://gronk', :tags => ['first_tag', 'second_tag'] } }
      it { should contain_sensu__check('examplecheck').with_custom({
        "runbook"            => "http://gronk",
        "ticket"             => false,
        "irc_channels"       => :undef,
        "tip"                => false,
        "project"            => false,
        "alert_after"        => "0",
        "page"               => false,
        "realert_every"      => "-1",
        "sla"                => "No SLA defined.",
        "team"               => "operations",
        "notification_email" => "undef",
        "habitat"            => "somehabitat",
        "tags"               => ['first_tag','second_tag'],
        }
      )}
    end
    context "with remediation" do
      let(:facts) { { :habitat => "somehabitat", :lsbdistid => 'Ubuntu', :osfamily => 'Debian', :lsbdistcodename => 'lucid', :operatingsystem => 'Ubuntu', :ipaddress => '127.0.0.1', :puppetversion => '3.6.2' } }
      let(:params) { {:command => '/bin/bar', :runbook => 'http://gronk', :remediation_action => '/bin/ls /', :remediation_retries => 2 } }
      it { should contain_sensu__check('examplecheck')
        .with_command('/etc/sensu/plugins/remediation.sh -n "examplecheck" -c /bin/bar -a /bin/ls\ / -r 2') \
      }
    end


    context 'with subdue' do
      let(:params) {{
        :command => 'foo', :runbook => 'http://gronk',
        :subdue => { 'bar' => 'baz' }
      }}
      it {
        should contain_sensu__check('examplecheck').with_subdue('bar' => 'baz')
      }
    end

    context 'with env_vars' do
      let(:params) {{
        :command => 'foo', :runbook => 'http://gronk',
        :env_vars => { 'VAR1' => '1', 'VAR2' => 'too' }
      }}
      it {
        should contain_sensu__check('examplecheck').with_command('VAR1=1 VAR2=too foo')
      }
    end
  end

end
