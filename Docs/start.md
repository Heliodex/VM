# Research in understanding

## The divide

There are many ways to compare the tools used to write software. One of these commonly-used metrics is **level** &ndash; tools are sometimes considered *high*-level or *low*-level.

In computer science, these terms are most commonly used to signify how far abstracted away the tool is from the hardware it runs on. High-level tools are characterised by generalisation of problems, automatic handling of underlying system operations, portability, and reliance on low-level tools, whereas low-level tools tend to provide control over specific system details, performance, and specialisation for particular types of system.

<img src="../Assets/Level1.svg" height="350" alt="Diagram showing high-level at the top and low-level at the bottom" />

The descriptors 'high' and 'low' mean what they do because of the way nearly all software is built, relying on hardware, hardware control layers, instruction set architectures, systems languages, transport & communication protocols, interpreters, libraries, applications, user interfaces... onwards and upwards forever.

<img src="../Assets/Level2.svg" height="350" alt="A similar diagram showing how tools build upwards on top of each other" />

From the other end of the scale, mathematical concepts can be thought of being built from the opposite direction. Founded on axioms written in natural language, abstract and normally considered very high-level, and built up through logic and theorems to become formalised and rigorous enough to be useful in practice.

<img src="../Assets/Level4.svg" height="350" alt="A diagram showing how mathematical tools build from the opposite end of the scale" />

Let's take 2 examples of systems for expressing computations: lambda calculus and Turing machines.

The untyped lambda calculus is built only from functions, parameters, and applications. All data must be expressed as parameters or functions, and expressions are evaluated using β-reduction, repeated substitution of parameters for their values.

The Turing machine is built only from an infinite tape of symbols and a head that can read and toggle symbols on the tape at its location and move left or right. The behaviour of the head is controlled by a machine that changes its state based on its current state and the symbol it reads, and programs are evaluated by letting the state machine run until it halts.

Lambda calculus is easily representable in standard mathematics, with standard function notation and parameters. A Turing machine is easily representable in machine code, with a section of memory for the tape and a table for defining possible states. As such, the systems can be thought of as high-level and low-level respectively.

<img src="../Assets/Level5.svg" height="350" alt="A diagram showing lambda calculus as high-level and turing machines as low-level" />

The Church-Turing thesis shows that these 2 models of computation have equivalent computational power, and that each can simulate the other &ndash; they are equal.

This shows there's nothing inherently preventing software from going in the opposite direction, for example if it were useful to write a hardware simulator in a high-level language. This could allow low-level implementation details and high-level simulation logic to be expressed with a coherent system.

<img src="../Assets/Level3.svg" height="350" alt="A similar diagram showing a low-level simulator built on top of a high-level interpreter" />

 If accurate enough, the tools used to build the system could then be built on top of the simulator. This could be done any number of times, resulting in an infinite loop of simulators built on top of themselves. This is an extremely powerful concept, though in practice isn't useful if a system isn't built with this in mind, as there will be a loss of efficiency at each level, eventually resulting in a program that is too slow (read: will not complete in the expected lifetime of the universe).

 Any simulation of a universe which contains a model of the machine used to run it cannot have the simulated machine run as fast as the physical machine, as every simulation has some level of overhead. However, it is possible to get remarkably close, which I will expand on in future.
