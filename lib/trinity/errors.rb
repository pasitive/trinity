module Trinity
  class AbstractMethodNotOverriddenError < StandardError
  end

  class NoSuchContactError < StandardError
  end

  class NoSuchTransitionError < StandardError
  end

  class NoSuchCustomFieldError < StandardError
  end
end