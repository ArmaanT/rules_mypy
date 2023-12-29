# Adapted from
# https://docs.pydantic.dev/latest/integrations/mypy/

from datetime import datetime
from typing import List, Optional

from pydantic import BaseModel


class Model(BaseModel):
    age: int
    # The following line would pass mypy if we didn't
    # have pydantic mypy plugin configured
    # first_name = "John"
    first_name: str = "John"
    last_name: Optional[str] = None
    signup_ts: Optional[datetime] = None
    list_of_ints: List[int]


m = Model(age=42, list_of_ints=[1, 2, 3])
