module Plain

service
  state Int = 0
  tools bump
  token from env "PLAIN_TOKEN"
end

fn bump(state: Int, _now: Time) : (Int, Int)
  (state + 1, state + 1)
end
