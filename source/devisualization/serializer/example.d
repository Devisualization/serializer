__EOF__

module cf.spew.serialization.example;
import cf.spew.serialization.udas;
import cf.spew.serialization.defs;
import std.variant : Variant;
struct Valid {}
struct Invalid {}

class E1C {}

@Valid
struct E1S {
	int a;
	E1C b;

	void serialize(void delegate(Variant) serializer) {
		serializer(Variant(a));
		serializer(Variant(b));
	}

	static {
		void deserialize(Variant delegate(Type) deserializer, out E1S ret) {
			ret = E1S(deserializer(Type.Int).get!int, deserializer(Type.Object).get!E1C);
		}
	}
}

@Valid
struct E2S {
	bool isA;

	union {
		int a;
		E1C b;
	}

	void serialize(void delegate(Variant) serializer) {
		serializer(Variant(isA));
		if (isA)
			serializer(Variant(a));
		else
			serializer(Variant(b));
	}
	
	static {
		void deserialize(Variant delegate(Type) deserializer, out E2S ret) {
			bool isA = deserializer(Type.Bool).get!bool;
			ret = E2S(isA);

			if (isA)
				ret.a = deserializer(Type.Int).get!int;
			else
				ret.b = deserializer(Type.Object).get!E1C;
		}
	}
}

@Invalid
struct E3S {
	bool isB;
	
	union {
		int a;
		E1C b;
	}
}

@Valid
struct E4S {
	@ChooseUnionValue(1)
	bool isB;

	@Union(1)
	union {
		int a;
		E1C b;
	}
}

@Valid
struct E5S {
	@ChooseUnionValue(1)
	bool isB;
	
	@Union(1)
	E5U value;
}

union E5U {
	int a;
	E1C b;
}

@Valid
struct E6S {
	@ChooseUnionValue(1)
	bool isA;
	
	@Union(1)
	union {
		@UnionValueMap(true)
		int a;

		@UnionValueMap(false)
		E1C b;
	}
}

@Invalid
struct E7S {
	@ChooseUnionValue(1)
	bool isA;
	
	@Union(1)
	union {
		@UnionValueMap(true)
		int a;
		
		@UnionValueMap(false)
		E1C b;

		// type != bool
		@UnionValueMap(8)
		ulong c;
	}
}

interface E8_IArchiverSQL : IArchiver {
	void hint_name(uint valueOffset, string v);
}

@Valid
struct E8S {
	int a;
	
	void serialize(void delegate(Variant) serializer, IArchiver archiver) {
		if (E8_IArchiverSQL archiverSQL = cast(E8_IArchiverSQL)archiver) {
			archiverSQL.hint_name(0, "key");
		}

		serializer(Variant(a));
	}
	
	static {
		void deserialize(Variant delegate(Type) deserializer, IArchiver archiver, out E8S ret) {
			if (E8_IArchiverSQL archiverSQL = cast(E8_IArchiverSQL)archiver) {
				archiverSQL.hint_name(0, "key");
			}

			ret = E8S(deserializer(Type.Int).get!int);
		}
	}
}
