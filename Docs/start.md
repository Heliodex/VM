# Research in understanding

## The divide

There are many ways to compare the tools used to write software. One of these commonly-used metrics is **level** &ndash; tools are sometimes considered *high*-level or *low*-level.

In computer science, these terms are most commonly used to signify how far abstracted away the tool is from the hardware it runs on. High-level tools are characterised by generalisation of problems, automatic handling of underlying system operations, portability, and reliance on low-level tools, whereas low-level tools tend to provide control over specific system details, performance, and specialisation for particular types of system.

The following diagram will be used to illustrate the relationship between high-level and low-level tools. Positions on the chart are extremely simplified and arguable, precision could be improved by adding more dimensions or factors such as complexity.

<img src="../Assets/Level1.svg" height="350" alt="Diagram showing high-level at the top and low-level at the bottom" />

The descriptors 'high' and 'low' mean what they do because of the way nearly all software is built, relying on hardware, hardware control layers, instruction set architectures, systems languages, transport & communication protocols, interpreters, libraries, applications, user interfaces... onwards and upwards forever.

<img src="../Assets/Level2.svg" height="350" alt="A similar diagram showing how tools build upwards on top of each other" />

From the other end of the scale, mathematical concepts can be thought of being built from the opposite direction. Founded on axioms written in natural language, abstract and normally considered very high-level, and built up through logic and theorems to become formalised and rigorous enough to be useful in practice.

Regardless of which end a system builds from, the ability to build on top of existing tools and abstractions is critical for implementing complex systems.

<img src="../Assets/Level4.svg" height="350" alt="A diagram showing how mathematical tools build from the opposite end of the scale" />

Let's take 2 examples of systems for expressing computations: lambda calculus and Turing machines.

The untyped lambda calculus is built only from functions, parameters, and applications. All data must be expressed as parameters or functions, and expressions are evaluated using β-reduction &ndash; repeated substitution of parameters for their values.  
Each function takes 1 parameter and results in 1 output value, both of which are functions, as functions are the only method of expressing data. Functions can be combined to create multi-parameter functions and multiple outputs, and recursion can be used to express iteration.

The Turing machine is built only from a set of infinite tapes of symbols from its alphabet and a head for each tape that can read and change symbols on the tape at its location and move left or right. The behaviour of the heads are controlled by a machine that changes its state based on its current state and the symbol it reads, and programs are evaluated by letting the state machine run until it halts.  
The simplest Turing machine has 1 tape and 2 symbols in its alphabet. The tape can also be semi-infinite, that is having only 1 end, though a truly infinite tape can be simpler to reason about as the behaviour at the end of the tape doesn't need to be considered.

Lambda calculus is easily representable in standard mathematics, with standard function notation and parameters. A Turing machine is easily representable in machine code, with a section of memory for the tape and a table for defining possible states. As such, the systems can be thought of as high-level and low-level respectively.

<img src="../Assets/Level5.svg" height="350" alt="A diagram showing lambda calculus as high-level and turing machines as low-level" />

These systems, easy to think of as worlds apart, share some remarkable similarities. The Halting problem states that, for any input program or formula, there is no algorithm to determine whether it will complete, resolve to a value, or halt execution, or whether it will run forever without completing. Both lambda calculus and Turing machines are subject to the Halting problem: in lambda calculus, an expression can evaluate to itself or another expression containing itself, and a Turing machine can enter a loop of states that never reaches a halting state.  
If there exists an algorithm to determine whether an input to any computational system will halt, then the computational system cannot be Turing complete. This does not mean that the system is not useful, and any Turing complete system can be restricted to a non-Turing complete subset of itself. Take, for example, a turing machine that halts after a N state transitions, or a lambda calculus that disallows more than N β-reductions. For a large enough N these systems might be able to calculate every practical computation problem in the universe. It will always be possible to construct a theoretical problem requiring more than N transitions/reductions to solve, though it may never be possible to construct a general program to practically determine whether the environment it is running in is *truly* turing-complete.

The Church-Turing thesis shows that these 2 models of computation have equivalent computational power, and that each can simulate the other &ndash; they are equal.

This shows there's nothing inherently preventing software from going in the opposite direction, for example if it were useful to write a hardware simulator in a high-level language. This could allow low-level implementation details and high-level simulation logic to be expressed with a coherent system.

<img src="../Assets/Level3.svg" height="350" alt="A similar diagram showing a low-level simulator built on top of a high-level interpreter" />

 If accurate enough, the tools used to build the system could then be built on top of the simulator. This could be done any number of times, resulting in an infinite loop of simulators built on top of themselves. This is an extremely powerful concept, though in practice isn't useful if a system isn't built with this in mind, as there will be a loss of efficiency at each level, eventually resulting in a program that is too slow (will not complete in the expected lifetime of the universe).

 Any simulation of a universe which contains a model of the machine used to run it cannot have the simulated machine run as fast as the physical machine, as every simulation has some level of overhead. However, it is possible to get remarkably close, which will be expanded on in later documents.

 ## Virtual machines

 A virtual machine is a software representation of a computer system. These can be split into 2 categories: system virtual machines, which accurately simulate a real-world computer system, and process virtual machines, which simulate an abstract environment that doesn't exist in hardware. This series of documents will focus chiefly on process virtual machines, hereinafter referred to as just VMs.

 The purpose of a process VM is to provide a platform-independent programming environment &ndash; a system that can be reimplemented and run on many different host environments, even if they're heavily sandboxed, and provide portability for programs written for them. VMs are commonly written for interpreted programming languages, languages that compile to VM machine code to then be run or distributed as either source code or VM code. Another common use is in emulation projects to create a programming environment with a retro feel for fantasy consoles or computers, their restrictive environments giving rise to creative tricks and workarounds.

 In some cases, when writing programs targeting a certain VM, the underlying system and its implementation can be ignored entirely. An entire world's worth of software can be built without caring about low-level implementation details &ndash; the floor can be raised and what is 'low-level' can be reconsidered, in a kind of ignorance that provides strength.

The smaller and simpler the design and implementation of a VM is, the more portable it and its suite of software on top of it becomes, and the easier it is to reason about the system as a whole, generally making it easier to write and maintain software for that VM.

<img src="../Assets/Hourglass.svg" height="350" alt="Hourglass diagram, showing the VM implementation built upon a platform layer, hosting the VM and its software ecosystem above it" />

After the design is complete and implementations are widespread, it may also be possible to remove the lower cone from the diagram entirely by providing a direct hardware implementation, a kind of VMPU, if its design is suited well enough for it.

In the above diagram, the lower cone represents the VM implementation, with the height showing how much abstraction is provided away from the underlying platform, the width of the footprint showing how much complexity there is to implement the VM, and the width of the tip representing the VM itself. It's represented as a cone due to the fact that the implementation complexity is greater than the complexity of the VM itself &ndash; if the VM were to have greater complexity, then it's likely that the implementation would as well.

One good set of targets to aim for might be a VM, as simple as possible, with an implementation that provides a maximum level of abstraction away from the base platform with a minimal implementation footprint. This provides a foundation for beginning work on design decisions. However, there is one factor that has not been considered yet: its performance.  
No VM design can strictly limit the performance of its implementation, though misguided design decisions could end up negatively impacting its aims in other ways. Take the example of a basic VM for implementing arithmetic, which might have operations (or 'opcodes', where applicable) for addition, subtraction, multiplication, and division. The VM design could certainly be simplified by removing every operation and replacing them with a single "increment by 1" instruction. Addition and subtraction would just be repeated increments, and multiplication and division would be repeated addition and subtraction. Thus the simplicity of the VM is maximised, but at the cost of performance, as every arithmetic operation would take far longer to complete. As such, a basic implementation might still be simpler, but its ability to perform useful work would be limited. Any implementation with a reasonable level of performance could recognise these algorithms for arithmetic operations and optimise them to be as efficient as the original design, but this new implementation might be more complex than an original design implementation.

This technique of moving complexity out of the VM design and into algorithms implemented on it is a powerful tradeoff, and the idea of optimising the performance of these algorithms will hereinafter be referred to as 'jets'. As a sufficiently (infinitely) clever interpreter would be able to solve any computation problem in constant time (O(1), though the 1 may be very large), the highest performance implementations for any given VM will likely use jets extensively at the cost of implementation complexity. The more interesting idea is whether they are required at all, or where to draw the line at having a minimally complex VM such that the simplest implementation, utilising no jets, can still perform "well enough" for practical use cases.

The alternative to this idea of a jetless VM is one where only the minimum instructions possible are available directly, and all others have to be built on top of them via jetted algorithms. This decreases the implementation complexity of the minimum working VM, allowing it to work correctly for the simplest programs, though perhaps not meeting performance requirements for larger ones. Again taking the example of the basic arithmetic VM, to achieve performance requirements, there may need to exist jets for the algorithms for addition, subtraction, multiplication, and division.  
The benefits of this approach are that a minimum working VM is easier to implement, and that when increased performance is required, the jets can be tested alongside their standard algorithmic counterparts to ensure they work correctly under all circumstances. The disadvantages may include the possibility that jets are more difficult to implement than standard operations, as well as the difficulty of recognising whether a given algorithm even needs to be jetted while the VM is running.

A VM relying so heavily on jets would also need to more carefully consider their inherent shortcomings, such as the requirement that jets must perform identically within the VM as the algorithms they replace. Failing to satisfy this requrement, for example by having a jet for an algorithm that returns incorrect results, could result in dire consequences &ndash; if a VM were to persist state then this state could be corrupted, if it were to require determinism then this determinism could be contaminated, and the otherwise perfect computational model of these VMs would be ruined. If the VM is implemented in a language that supports a formal specification or proof system, this risk can be minimised.  
It could be argued that any bug could appear in any feature of a VM implementation, regardless of whether it uses a jet for that feature, and so this risk is not unique to jets. Thus the focus should be to minimise complexity in all areas of the implementation, and whether jets are a useful tool for doing so will be at the discretion of the designers of the VM and the programmers of its implementations.

However, there does exist one great benefit of a certain type of jet implementation, which will be noted later on.

All things considered, the costs and benefits jets must be carefully weighed against each other, both for the VM and the environments it may run in. The truth is that any VM will almost certainly need to run on a wide variety of existing hardware and software to be seen as useful, which means implementing the VM many times over in many different programming environments. And for most popular programming languages, the complexity required for performing some complicated operations is surprisingly low &ndash; for a common implementation definition of 'number', multiplying or dividing a number is not a significant complexity jump from simply incrementing it by 1. A VM designer may wish to take advantage of any easily implementable operations available and allow them to be used directly, due to their relatively small impact on implementation complexity.
