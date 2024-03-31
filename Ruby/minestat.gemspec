Gem::Specification.new do |spec|
  spec.name = "minestat"
  spec.version = "3.0.5"
  spec.authors = ["Lloyd Dilley"]
  spec.email = ["minecraft@frag.land"]
  spec.summary = "Minecraft server status checker"
  spec.homepage = "https://github.com/FragLand/minestat"
  spec.description = "MineStat polls Minecraft server data such as version," \
                  " motd, current players, and max players."
  spec.license = "GPL-3.0"
  spec.files = ["lib/minestat.rb", "example.rb", ".yardopts"]
  spec.extra_rdoc_files = Dir["ChangeLog.md", "License.txt", "ReadMe.md"]
  spec.required_ruby_version = ">= 2.2.0"
end
