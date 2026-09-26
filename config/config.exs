import Config

# Ash 3 requires a default string-length count for min/max length constraints;
# the generated composition fixture's uuid_primary_key triggers this verifier.
config :ash, default_string_length_count: :codepoints
