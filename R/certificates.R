# The practising certificate types, in the order the dashboard shows them.
#
# - certificate: the full name stored in the database.
# - label: the short name the dashboard uses.
# - form_option: the value the directory's search form uses.
# - pattern: how to find the certificate in a person's list of certificates.
#
# The directory spells "With-Profits" with a hyphen on its search form, and
# has listed it both with and without the hyphen.
certificates <- tribble(
  ~certificate,                               ~label,
  "Chief Actuary (Life)",                     "Life",
  "Chief Actuary (Life, Non-Directive)",      "Life (Non-Directive)",
  "With Profits Actuary",                     "With Profits",
  "Chief Actuary (non-Life with Lloyd's)",    "Non-Life with Lloyd's",
  "Chief Actuary (non-Life without Lloyd's)", "Non-Life ex Lloyd's",
  "Lloyd's Syndicate Actuary",                "Syndicate",
  "Scheme Actuary",                           "Scheme"
) |>
  mutate(
    form_option = str_replace(certificate, "With Profits", "With-Profits"),
    pattern = str_replace(
      str_escape(certificate),
      "With Profits",
      "With[- ]Profits"
    )
  )
