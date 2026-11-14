module Answer
expose city_customers
use Shop{Shop}

fn city_customers(shop: Shop, city: Text) : List(Text)
  shop.customers.in_city(city).map(fn(customer) customer.name end).sort
end
