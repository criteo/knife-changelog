name 'test_policy'

run_list [
  'recipe[users]',
  'recipe[sudo]',
]

default_source :supermarket, "https://supermarket.chef.io"
