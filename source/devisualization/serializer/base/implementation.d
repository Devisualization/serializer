﻿module devisualization.serializer.base.implementation;
import devisualization.serializer.base.type_reflectors;
import devisualization.serializer.udas;
import devisualization.serializer.defs;
import std.variant : Variant;
import std.experimental.allocator : IAllocator;

public import devisualization.serializer.base.type_reflectors : addType;

// debug=DevisualizationDevisualizationShowSerializerDebugMessages;

struct BaseSerializer {
	@disable
	this(this);
	
	private {
		TypeReflector[] handlers;
		IArchiver archiver;
		
		bool needToSort;
		TypeReflector[] primitives;

		IAllocator alloc;
	}
	
	void setArchiver(IArchiver archiver) { this.archiver = archiver; }
	IArchiver getArchiver() { return archiver; }

	void setAllocator(IAllocator alloc) { this.alloc = alloc; }

	void reset() {
		archiver.reset();
		alloc.deallocateAll();
	}

	void serialize(Variant value, bool withObjectHierarchyLookup=true) {
		if (withObjectHierarchyLookup)
			serialize!true(value);
		else
			serialize!false(value);
	}

	void serialize(bool withObjectHierarchyLookup)(Variant value) {
		uint numJumps;
		TypeReflector* got = lookup(value.type, withObjectHierarchyLookup, numJumps);
		
		if (got is null)
			throw new TypeNotSerializable("Type is not registered");
		else
			got.fromType(value, archiver, &serialize!withObjectHierarchyLookup);
	}

	Variant deserialize(TypeInfo typeId, bool withObjectHierarchyLookup=true) {
		if (withObjectHierarchyLookup)
			return deserialize!true(typeId);
		else
			return deserialize!false(typeId);
	}

	Variant deserialize(bool withObjectHierarchyLookup)(TypeInfo typeId) {
		uint numJumps;
		TypeReflector* got = lookup(typeId, withObjectHierarchyLookup, numJumps);
		
		if (got is null)
			throw new TypeNotSerializable("Type is not registered");
		else
			return got.toType(archiver, alloc, &deserialize);
	}
	
	void addTypeReflector(TypeReflector handlers, bool replace=false) {
		uint numJumps;
		TypeReflector* got = lookup(handlers.typeInfo, false, numJumps);

		if (got is null)
			this.handlers ~= handlers;
		else if (replace)
			*got = handlers;

		needToSort = true;
	}
	
	private {
		TypeReflector* lookup(TypeInfo typeInfo, bool withObjectHierarchyLookup, ref uint numJumps) {
			import std.algorithm : canFind;
			
			debug(DevisualizationShowSerializerDebugMessages) {
				import std.stdio;
				writeln("Looking up: ", typeInfo);
				writeln;
			}
			
			if (needToSort)
				sort();

			bool isComplexType = true;

			TypeInfo_Class claszTypeInfo;
			if (TypeInfo_Class clasz = cast(TypeInfo_Class)typeInfo)
				claszTypeInfo = clasz;
			else if (TypeInfo_Interface clasz = cast(TypeInfo_Interface)typeInfo)
				claszTypeInfo = clasz.info;
			else if (TypeInfo_Array clasz = cast(TypeInfo_Array)typeInfo)
				withObjectHierarchyLookup = false;
			else if (TypeInfo_Enum clasz = cast(TypeInfo_Enum)typeInfo)
				withObjectHierarchyLookup = false;
			else
				isComplexType = false;
			
			if (isComplexType) {
				bool fallbackIsClass;
				uint stepsToFallback = uint.max;
				TypeReflector* fallback, got;
				uint numJumpsT;
				
				foreach_reverse(i, ref handler; handlers[primitives.length .. $]) {
					debug(DevisualizationShowSerializerDebugMessages) {
						writeln(" ", i, ": ", handler.typeInfo);
					}
					
					if (handler.typeInfo.toString() == typeInfo.toString()) {
						numJumps++;
						return &handler;
					}
				}
				
				if (withObjectHierarchyLookup) {
					if (claszTypeInfo.base !is null) {
						debug(DevisualizationShowSerializerDebugMessages) {
							writeln("> base ", claszTypeInfo.base);
						}
						
						numJumpsT = 0;
						got = lookup(claszTypeInfo.base, true, numJumpsT);
						
						if (got !is null) {
							if (TypeInfo_Class clasz = cast(TypeInfo_Class)got.typeInfo) {
								if ((stepsToFallback > numJumpsT && fallbackIsClass) || !fallbackIsClass) {
									stepsToFallback = numJumpsT;
									fallback = got;
									fallbackIsClass = true;
								}
							} else if (TypeInfo_Interface clasz = cast(TypeInfo_Interface)got.typeInfo) {
								if (stepsToFallback > numJumpsT && !fallbackIsClass) {
									stepsToFallback = numJumpsT;
									fallback = got;
								}
							}
						}
						
						debug(DevisualizationShowSerializerDebugMessages) {
							writeln("< base ", claszTypeInfo.base);
						}
					}
					
					foreach(i, ref inter; claszTypeInfo.interfaces) {
						debug(DevisualizationShowSerializerDebugMessages) {
							writeln("> interface ", i, ": ", inter.classinfo);
						}
						
						numJumpsT = 0;
						got = lookup(inter.classinfo, true, numJumpsT);
						
						if (got !is null) {
							if (TypeInfo_Class clasz = cast(TypeInfo_Class)got.typeInfo) {
								if ((stepsToFallback > numJumpsT && fallbackIsClass) || !fallbackIsClass) {
									stepsToFallback = numJumpsT;
									fallback = got;
									fallbackIsClass = true;
								}
							} else if (TypeInfo_Interface clasz = cast(TypeInfo_Interface)got.typeInfo) {
								if (stepsToFallback > numJumpsT && !fallbackIsClass) {
									stepsToFallback = numJumpsT;
									fallback = got;
								}
							}
						}
						
						debug(DevisualizationShowSerializerDebugMessages) {
							writeln("< interface ", i, ": ", inter.classinfo);
						}
					}
				}
				
				if (stepsToFallback < uint.max)
					numJumps += stepsToFallback;
				
				debug(DevisualizationShowSerializerDebugMessages) {
					writeln(fallback);
				}
				
				return fallback;
			} else {
				foreach_reverse(i, ref handler; primitives) {
					debug(DevisualizationShowSerializerDebugMessages) {
						writeln(" ", i, ": ", handler.typeInfo);
					}
					
					if (handler.typeInfo is typeInfo) {
						numJumps++;
						return &handler;
					}
				}

				return null;
			}
		}
		
		void sort() {
			import std.algorithm.sorting : multiSort;
			
			multiSort!(
				(a, b) => a.type < b.type,
				(a, b) => a.typeInfo is typeid(ISerializer),
				(a, b) => (cast(TypeInfo_Interface)a.typeInfo) !is null && (cast(TypeInfo_Class)b.typeInfo),
				(a, b) => a.typeInfo < b.typeInfo
				)(handlers);
			
			this.primitives = null;
			foreach(i, ref handler; this.handlers) {
				if (TypeInfo_Class clasz = cast(TypeInfo_Class)handler.typeInfo) {
					this.primitives = this.handlers[0 .. i];
					break;
				} else if (TypeInfo_Interface clasz = cast(TypeInfo_Interface)handler.typeInfo) {
					this.primitives = this.handlers[0 .. i];
					break;
				} else if (TypeInfo_Array clasz = cast(TypeInfo_Array)handler.typeInfo) {
					this.primitives = this.handlers[0 .. i];
					break;
				} else if (TypeInfo_Enum clasz = cast(TypeInfo_Enum)handler.typeInfo) {
					this.primitives = this.handlers[0 .. i];
					break;
				}
			}
			if (this.primitives is null)
				this.primitives = this.handlers;
			
			needToSort = false;
		}
	}
}

interface Foo {}
interface FooBar : Foo {}
interface FooBared : Foo {}

class A {}
class AB : Foo {}
class ABC : FooBar {}
class Lastly : FooBar {}

abstract class Model : ISerializable {
	void serialize(void delegate(Variant) serializer, IArchiver archiver) {}
	void deserialize(Variant delegate(TypeInfo) deserializer, IArchiver archiver, IAllocator alloc, out ISerializable ret) {}
}

class Sarvy : Model {}

enum MyEnumFoo {
	A, B
}

enum MyEnumFoo2 {
	C, D
}

// if you need this code block, its because you're modifying this file
version(none) {
	shared static this() {
		BaseSerializer base;
		
		base.addType!bool;
		base.addType!ubyte;  base.addType!byte;
		base.addType!ushort; base.addType!short;
		base.addType!uint;   base.addType!int;
		base.addType!ulong;  base.addType!long;
		base.addType!float;  base.addType!double;
		base.addType!string; base.addType!wstring; base.addType!dstring;
		base.addType!Object;

		base.addType!(bool[]);
		base.addType!(ubyte[]);  base.addType!(byte[]);
		base.addType!(ushort[]); base.addType!(short[]);
		base.addType!(uint[]);   base.addType!(int[]);
		base.addType!(ulong[]);  base.addType!(long[]);
		base.addType!(float[]);  base.addType!(double[]);
		base.addType!(string[]); base.addType!(wstring[]); base.addType!(dstring[]);
		base.addType!(Object[]);

		base.addType!MyEnumFoo;
		//base.addType!Foo; base.addType!FooBar; base.addType!FooBared;
		base.addType!A;   base.addType!AB;     base.addType!ABC;

		void test(T)() {
			import std.stdio : writeln;
			import std.traits : Unqual, ForeachType, isDynamicArray;

			TypeInfo typeInfoOriginal = typeid(T);
			TypeInfo typeInfo;

			debug(all) {
				static if (isDynamicArray!T) {
					typeInfo = typeid(Unqual!(ForeachType!(Unqual!T))[]);
				} else static if (is(T == enum)) {
					typeInfo = typeInfoOriginal;
				} else {
					typeInfo = typeid(Unqual!T);
				}
			} else {
				typeInfo = typeInfoOriginal;
			}

			uint numJumps;
			TypeReflector* got;
			
			//
			
			numJumps = 0;
			got = base.lookup(typeInfo, true, numJumps);
			
			writeln("- With object lookup");
			if (got !is null)
				writeln("  For ", typeInfoOriginal, ", got ", got.typeInfo);
			else
				writeln("  For ", typeInfoOriginal, ", got null");
			
			//
			
			numJumps = 0;
			got = base.lookup(typeInfo, false, numJumps);
			
			writeln("- Without object lookup");
			if (got !is null)
				writeln("  For ", typeInfoOriginal, ", got ", got.typeInfo);
			else
				writeln("  For ", typeInfoOriginal, ", got null");
			
			//

			writeln;
		}
		
		test!int;
		test!bool;
		test!(ubyte[]);
		test!(uint[]);
		test!(int[]);
		test!string;
		test!wstring;
		test!(char[]);
		test!MyEnumFoo;
		test!MyEnumFoo2;
		test!ISerializable;
		test!Foo; test!FooBar; test!FooBared;
		test!AB;
		test!ABC;
		test!Lastly;
		test!Sarvy;
	}
}