import Foundation
import MLX
import MLXNN

class DummyModule: Module {
    @ModuleInfo(key: "my_proj") var myProj: Module
    override init() {
        self._myProj.wrappedValue = Linear(10, 10)
        super.init()
    }
}

let m = DummyModule()
print("Module initialized")
let updates = [("my_proj", Linear(10, 10))]
m.update(modules: updates)
print("Module updated successfully!")
