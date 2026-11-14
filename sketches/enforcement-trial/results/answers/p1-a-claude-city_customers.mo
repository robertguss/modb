module Answer
expose city_customers
use Shop{Shop}

fn city_customers(shop: Shop, city: Text) : List(Text)
  shop.customers.values.filter(fn(customer) customer.city == city end).map(fn(customer) customer.name end).sort
end
