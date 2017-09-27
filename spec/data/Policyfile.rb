name 'test_policy'

run_list [
  'recipe[uptodate]',
  'recipe[second_out_of_date]',
  'recipe[outdated1]'
]

default_source :supermarket, 'https://mysupermarket.io'
default_source :supermarket, 'https://mysupermarket2.io'
