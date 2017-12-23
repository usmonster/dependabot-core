# frozen_string_literal: true

require "spec_helper"
require "dependabot/dependency"
require "dependabot/dependency_file"
require "dependabot/update_checkers/python/pip"
require_relative "../shared_examples_for_update_checkers"

RSpec.describe Dependabot::UpdateCheckers::Python::Pip do
  it_behaves_like "an update checker"

  before do
    stub_request(:get, pypi_url).to_return(status: 200, body: pypi_response)
  end
  let(:pypi_url) { "https://pypi.python.org/simple/luigi" }
  let(:pypi_response) { fixture("python", "pypi_simple_response.html") }

  let(:checker) do
    described_class.new(
      dependency: dependency,
      dependency_files: dependency_files,
      credentials: [
        {
          "host" => "github.com",
          "username" => "x-access-token",
          "password" => "token"
        }
      ]
    )
  end

  let(:dependency_files) do
    [
      Dependabot::DependencyFile.new(
        name: "requirements.txt",
        content: fixture("python", "requirements", "version_specified.txt")
      )
    ]
  end
  let(:dependency) do
    Dependabot::Dependency.new(
      name: "luigi",
      version: "2.0.0",
      requirements: [
        {
          file: "requirements.txt",
          requirement: "==2.0.0",
          groups: [],
          source: nil
        }
      ],
      package_manager: "pip"
    )
  end

  describe "#can_update?" do
    subject { checker.can_update? }

    context "given an outdated dependency" do
      it { is_expected.to be_truthy }
    end

    context "given an up-to-date dependency" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.6.0",
          requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.6.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end
      it { is_expected.to be_falsey }
    end
  end

  describe "#latest_version" do
    subject { checker.latest_version }
    it { is_expected.to eq(Gem::Version.new("2.6.0")) }

    context "when the pypi link resolves to a redirect" do
      let(:redirect_url) { "https://pypi.python.org/LuiGi/json" }

      before do
        stub_request(:get, pypi_url).
          to_return(status: 302, headers: { "Location" => redirect_url })
        stub_request(:get, redirect_url).
          to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq(Gem::Version.new("2.6.0")) }
    end

    context "when the pypi link fails at first" do
      before do
        stub_request(:get, pypi_url).
          to_raise(Excon::Error::Timeout).then.
          to_return(status: 200, body: pypi_response)
      end

      it { is_expected.to eq(Gem::Version.new("2.6.0")) }
    end

    context "when the pypi link resolves to a 'Not Found' page" do
      let(:pypi_response) { "Not Found (no releases)" }

      it { is_expected.to be_nil }
    end

    context "when the dependency name isn't normalised" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "Luigi_ext",
          version: "2.0.0",
          requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end
      let(:pypi_url) { "https://pypi.python.org/simple/luigi-ext" }
      let(:pypi_response) do
        fixture("python", "pypi_simple_response_underscore.html")
      end
      it { is_expected.to eq(Gem::Version.new("2.6.0")) }
    end

    context "when the user's current version is a pre-release" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.6.0a1",
          requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.6.0a1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end
      it { is_expected.to eq(Gem::Version.new("2.7.0b1")) }
    end

    context "and the current requirement has a pre-release requirement" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: nil,
          requirements: [
            {
              file: "requirements.txt",
              requirement: ">=2.6.0a1",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end
      it { is_expected.to eq(Gem::Version.new("2.7.0b1")) }
    end

    context "with a custom index-url" do
      context "set in a pip.conf file" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "pip.conf",
              content: fixture("python", "conf_files", "custom_index")
            )
          ]
        end
        let(:pypi_url) do
          "https://pypi.weasyldev.com/weasyl/source/+simple/luigi"
        end

        it { is_expected.to eq(Gem::Version.new("2.6.0")) }
      end

      context "set in a requirements.txt file" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("python", "requirements", "custom_index.txt")
            )
          ]
        end
        let(:pypi_url) do
          "https://pypi.weasyldev.com/weasyl/source/+simple/luigi"
        end

        it { is_expected.to eq(Gem::Version.new("2.6.0")) }
      end
    end

    context "with an extra-index-url" do
      let(:extra_url) do
        "https://pypi.weasyldev.com/weasyl/source/+simple/luigi"
      end
      let(:extra_response) do
        fixture("python", "pypi_simple_response_extra.html")
      end
      before do
        stub_request(:get, extra_url).
          to_return(status: 200, body: extra_response)
      end

      context "set in a pip.conf file" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "pip.conf",
              content: fixture("python", "conf_files", "extra_index")
            )
          ]
        end

        its(:to_s) { is_expected.to eq("3.0.0+weasyl.2") }
      end

      context "set in a requirements.txt file" do
        let(:dependency_files) do
          [
            Dependabot::DependencyFile.new(
              name: "requirements.txt",
              content: fixture("python", "requirements", "extra_index.txt")
            )
          ]
        end

        its(:to_s) { is_expected.to eq("3.0.0+weasyl.2") }
      end
    end
  end

  describe "#latest_resolvable_version" do
    subject { checker.latest_resolvable_version }
    it { is_expected.to eq(Gem::Version.new("2.6.0")) }
  end

  describe "#updated_requirements" do
    subject { checker.updated_requirements.first }
    its([:requirement]) { is_expected.to eq("==2.6.0") }

    context "when the requirement was in a constraint file" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0.0",
          requirements: [
            {
              file: "constraints.txt",
              requirement: "==2.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end

      its([:file]) { is_expected.to eq("constraints.txt") }
    end

    context "when the requirement had a lower precision" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0",
          requirements: [
            {
              file: "requirements.txt",
              requirement: "==2.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end

      its([:requirement]) { is_expected.to eq("==2.6.0") }
    end

    context "when there were multiple requirements" do
      let(:dependency) do
        Dependabot::Dependency.new(
          name: "luigi",
          version: "2.0.0",
          requirements: [
            {
              file: "constraints.txt",
              requirement: "==2.0.0",
              groups: [],
              source: nil
            },
            {
              file: "requirements.txt",
              requirement: "==2.0.0",
              groups: [],
              source: nil
            }
          ],
          package_manager: "pip"
        )
      end

      it "updates both requirements" do
        expect(checker.updated_requirements).to match_array(
          [
            {
              file: "constraints.txt",
              requirement: "==2.6.0",
              groups: [],
              source: nil
            },
            {
              file: "requirements.txt",
              requirement: "==2.6.0",
              groups: [],
              source: nil
            }
          ]
        )
      end
    end
  end
end
