// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.30;

contract ReputationVanet {
    constructor(address[] memory _owners) {
        uint256 ownersLength = _owners.length;
        require(
            ownersLength >= requiredOwnersConfirmation,
            "Input less than requirement"
        );
        for (uint256 i; i < ownersLength;) {
            // require(owner != address(0), "invalid owner");
            owners[_owners[i]] = true;
            unchecked {
                ++i;
            }
        }
        ownerCount = ownersLength;

        // Fuzzy Logic
        // describe terms for each variable
        fuzzyInput.terms[1].mfParams = [0, 0, 400, 500]; // low
        fuzzyInput.terms[2].mfParams = [400, 600, 700, 900]; // medium
        fuzzyInput.terms[3].mfParams = [700, 900, 1000, 1000]; // high

        fuzzyOutput.terms[1].mfParams = [0, 0, 0, 200]; // very low
        fuzzyOutput.terms[2].mfParams = [0, 200, 200, 400]; // low
        fuzzyOutput.terms[3].mfParams = [300, 500, 500, 700]; // medium
        fuzzyOutput.terms[4].mfParams = [600, 800, 800, 1000]; // high
        fuzzyOutput.terms[5].mfParams = [800, 1000, 1000, 1000]; // very high

        // describe system rules
        // It's important to preserve the same order in description
        // as you had when defined inputs
        fuzzyRules[0].conditions = [1, 1];
        fuzzyRules[0].conclusion = 1; // very low

        fuzzyRules[1].conditions = [1, 2];
        fuzzyRules[1].conclusion = 2; // low

        fuzzyRules[2].conditions = [1, 3];
        fuzzyRules[2].conclusion = 3; // medium

        fuzzyRules[3].conditions = [2, 1];
        fuzzyRules[3].conclusion = 2; // low

        fuzzyRules[4].conditions = [2, 2];
        fuzzyRules[4].conclusion = 3; // medium

        fuzzyRules[5].conditions = [2, 3];
        fuzzyRules[5].conclusion = 4; // high

        fuzzyRules[6].conditions = [3, 1];
        fuzzyRules[6].conclusion = 3; // medium

        fuzzyRules[7].conditions = [3, 2];
        fuzzyRules[7].conclusion = 4; // high

        fuzzyRules[8].conditions = [3, 3];
        fuzzyRules[8].conclusion = 5; // very high
    }

    struct ownerFunctionTransaction {
        uint40 functionID;
        address sender;
        address[] addressList;
        mapping(address => bool) confirmList;
        bool executed;
        uint256 confirmations;
    }

    struct Node {
        bool preTrust;
        mapping(uint256 => Event) events;
        mapping(uint256 => Vote) votes;
        uint256 eventsLength;
        uint256 votesLength;
        mapping(uint256 => uint256) eventsIDIndex;
        mapping(uint256 => uint256) votesIDIndex;
        uint40 currentReputation;
        uint40 currentHonesty;
        bool exist;
    }

    struct Vote {
        /**
         * Create vote feedback.
         */
        uint256 timestamp; // timestamp of event
        uint40 honesty; // honesty value of this vote
        uint40 honestyWeight; // weight of honesty based on event feedback weight
    }

    struct Event {
        /**
         * Create event feedback gathering contract.
         *
         * @param _eventID ID of event
         * @param _eventType Type of event based on importance 0=Minor Event, 1=Moderate Event, 2=Severe Event
         *
         */
        uint256 eventID;
        uint256 eventIndex;
        uint40 eventType;
        uint40 eventREP;
        uint40 criticalFactor;
        uint256 timestamp; // timestamp of when event is created
        bool msgTrustResult; // False is majority negative, True is majority positive trust
        bool locTrustResult;
        uint40 msgTrustGoodWeight; // weight of accumulated good feedbacks for message
        uint40 locTrustGoodWeight;
        uint40 msgTrustBadWeight; // weight of accumulated bad feedbacks for message
        uint40 locTrustBadWeight;
        uint40 msgTrustWeight; // weight of accumulated final feedbacks for message
        uint40 locTrustWeight;
        uint40 penalty;
        uint256 feedbackCount;
        int256[2] coordinate;
        uint8 finish;
        address rsuAddress; // associated RSU address that receive the event
        mapping(address => EventFeedbackProvider) providers; // list of allocated feedback providers
        mapping(uint256 => address) providerAdrIndex;
    } 

    struct EventFeedbackProvider {
        uint40 weight; // weight that this provider have for feedback
        bool sent; // if true, that entity already sent feedback
        bool msgFeedback; // massage feedback value
        bool locFeedback; // location feedback value
    }

    struct LinguisticVariable {
        /**
         * Describes a Linguistic Variable - parameter for fuzzy inference system
         * It is a linguistic expression (one or more words) labeling an information
         * range always 0 to 10
         */
        bool isTrue;
        mapping(uint8 => Term) terms;
    }

    struct Rule {
        /**
         * Describe a rule for fuzzy inference system.
         * Rule is:
         * 1) Matching for every linguistic variable with one of it terms.
         * 2) connection "And" only available for this implementation
         * 3) Weight coefficient of Rule. Or how much rule will effort on system's conclusion. We assume weight always 1 here
         */
        uint8[2] conditions;
        uint8 conclusion;
    }

    struct Term {
        /**
         * Describes Term for linguistic variables.
         * Term is a fuzzy definition of some variable. Like 'tall', 'low' - about height
         * mfType type of membership functions. Only trapezoidal available
         * uint256 mapping;  // replace name to save gas with level instead like 0, 1, 2
         */
        bool isTrue;
        uint40[4] mfParams; //  mfParams parameters of the membership function.
    }

    struct CorrectedTerm {
        /**
         * Describes Term limited by belief degree.
         */
        uint40[4] mfParams; //  mfParams parameters of the membership function from term.
        uint40 beliefDegree; // number
    }

    mapping(address => bool) public owners;
    uint256 public requiredOwnersConfirmation = 1; // number of owner required for transaction to be confirmed
    uint256 public ownerTransactionCount;
    uint256 public ownerCount;

    mapping(uint256 => ownerFunctionTransaction) public ownerTransactions;

    mapping(address => Node) public nodes;
    mapping(address => bool) public rsus;
    mapping(uint256 => address) internal eventsOwner;

    uint256 internal eventDuration = 3600;
    uint40 internal penaltyRate = 250; // in scale where 0.01 is 100

    // Value is in scale of 1 = 1000
    uint40[5] internal eventRepRequirement = [100, 200, 300, 400, 500]; // Reputation value requirement for each event critical level
    //

    // Value is in scale of 1 = 100
    uint40[5] internal eventCriticalLevelFactor = [1, 2, 3, 4, 5]; // Critical level factor to event trust weight for each critical level
    // Time decay alpha value
    // NOTE: this list is time decay by day with alpha span 2 / 31
    // The value must be changed for different alpha
    uint40[69] internal timeDecayList = [
    100, // day 0
    93,
    87,
    81,
    76,
    71,
    66,
    62,
    58,
    54,
    51,
    47,
    44,
    41,
    39,
    36,
    34,
    31,
    29,
    27,
    26,
    24,
    22,
    21,
    19,
    18,
    17,
    16,
    15,
    14,
    13,
    12,
    11,
    10,
    10,
    9,
    8,
    8,
    7,
    7,
    6,
    6,
    5,
    5,
    5,
    4,
    4,
    4,
    3,
    3,
    3,
    3,
    3,
    2,
    2,
    2,
    2,
    2,
    2,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1,
    1 // day 68
    ];

    // Fuzzy vairables
    LinguisticVariable internal fuzzyInput;
    LinguisticVariable internal fuzzyOutput;
    mapping(uint8 => Rule) internal fuzzyRules;

    // MODIFIERS
    modifier onlySmartContractOwner() {
        require(owners[msg.sender], "Only owner can perform this task");
        _;
    }

    modifier onlyNode() {
        require(nodes[msg.sender].exist, "Node not existed");
        _;
    }

    function submitEvent(
        uint40 eventType,
        int256[2] memory coordinate,
        address rsuAddress
    ) external onlyNode returns (bool) {
        unchecked {
            Node storage node = nodes[msg.sender];
            require(rsus[rsuAddress], "RSU not exist");
            (uint40 msgNumerator, uint40 locNumerator) = feedbackAggregation(
                msg.sender
            );
            node.currentReputation = currentReputation(
                msgNumerator,
                locNumerator
            );
        // can only submit event if reputation pass threshold
            if (node.currentReputation >= eventRepRequirement[eventType]) {
                uint256 eventID = uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            msg.sender,
                            eventType,
                            coordinate,
                            rsuAddress,
                            node.currentReputation
                        )
                    )
                );
                Event storage newEvent = node.events[node.eventsLength];
                node.eventsIDIndex[eventID] = node.eventsLength;
                eventsOwner[eventID] = msg.sender;
                newEvent.eventID = eventID;
                newEvent.eventType = eventType;
                newEvent.eventREP = node.currentReputation;
                newEvent.timestamp = block.timestamp; // timestamp of when event is created
                newEvent.coordinate = coordinate;
                newEvent.rsuAddress = rsuAddress;
                newEvent.criticalFactor = eventCriticalLevelFactor[eventType];
                ++node.eventsLength;
                return true;
            } else {
                return false;
            }
        }
    }

    // function addTestEvent(uint40 howMany) external {
    //     unchecked {
    //         // can only submit event if reputation pass threshold
    //         for (uint256 p; p < howMany; ) {
    //             Node storage node = nodes[msg.sender];
    //             Event storage newEvent = node.events[node.eventsLength];
    //             uint256 eventID = node.eventsLength;
    //             node.eventsIDIndex[eventID] = node.eventsLength;
    //             eventsOwner[eventID] = msg.sender;
    //             newEvent.eventID = eventID;
    //             newEvent.eventType = 1;
    //             newEvent.eventREP = node.currentReputation;
    //             newEvent.timestamp = block.timestamp; // timestamp of when event is created
    //             newEvent.criticalFactor = 3;
    //             newEvent.locTrustGoodWeight = 5000;
    //             newEvent.locTrustBadWeight = 10000;
    //             newEvent.msgTrustGoodWeight = 100000;
    //             newEvent.locTrustWeight = 15000;
    //             newEvent.msgTrustWeight = 100000;
    //             newEvent.feedbackCount = 2;
    //             ++node.eventsLength;
    //             ++p;
    //         }
    //     }
    // }

    // function addTestFinishedEvent(uint40 howMany) external {
    //     unchecked {
    //         // can only submit event if reputation pass threshold
    //         for (uint256 p; p < howMany; ) {
    //             Node storage node = nodes[msg.sender];
    //             Event storage newEvent = node.events[node.eventsLength];
    //             uint256 eventID = node.eventsLength;
    //             node.eventsIDIndex[eventID] = node.eventsLength;
    //             eventsOwner[eventID] = msg.sender;
    //             newEvent.eventID = eventID;
    //             newEvent.eventType = 1;
    //             newEvent.eventREP = node.currentReputation;
    //             newEvent.timestamp = block.timestamp; // timestamp of when event is created
    //             newEvent.criticalFactor = 3;
    //             // newEvent.locTrustResult = true;
    //             newEvent.msgTrustResult = true;
    //             newEvent.locTrustWeight = 100;
    //             newEvent.msgTrustWeight = 100;
    //             newEvent.feedbackCount = 1;
    //             newEvent.finish = 1;
    //             newEvent.penalty = 250;
    //             ++node.eventsLength;
    //             ++p;
    //         }
    //     }
    // }

    /*
     * @dev Give 'providers' the right to send feedback in this process. May only be called by event RSU and process not ended.
     * @param address list of feedback providers
     */
    function giveEventFeedbackRight(
        address eventOwnerAddress,
        uint256 eventID,
        address[] memory providerList
    ) external {
        unchecked {
            Node storage thisNode = nodes[eventOwnerAddress];
            Event storage thisEvent = thisNode.events[
                                thisNode.eventsIDIndex[eventID]
                ];
            require(thisEvent.eventID == eventID, "Event not existed");
            require(
                block.timestamp - thisEvent.timestamp < eventDuration,
                "Event already expired"
            );
            require(
                msg.sender == thisEvent.rsuAddress,
                "You are not event's RSU"
            );
            uint256 providerListLength = providerList.length;
            for (uint256 p; p < providerListLength;) {
                require(
                    eventOwnerAddress != providerList[p],
                    "Can not give right to event owner."
                );
                require(
                    !thisEvent.providers[providerList[p]].sent,
                    "Already sent feedback."
                );

                if (nodes[providerList[p]].preTrust) {
                    // pre-trusted node
                    thisEvent.providers[providerList[p]].weight = 500; // @param change pretrusted weight as appropriate
                } else {
                    thisEvent.providers[providerList[p]].weight = 100; // @param change node weight as appropriate
                }
                ++p;
            }
        }
    }

    /*
     * @dev Give feedback (including weight delegated to provider) to event.
     * @param choice index of choice in the choices array
     */
    function submitFeedback(
        uint256 eventID,
        bool msgTrust,
        bool locTrust
    ) external {
        unchecked {
            address MsgSender = msg.sender;
            Node storage thisNode = nodes[eventsOwner[eventID]];
            Event storage thisEvent = thisNode.events[
                                thisNode.eventsIDIndex[eventID]
                ];
            EventFeedbackProvider storage provider = thisEvent.providers[
                            MsgSender
                ];
            require(thisEvent.eventID == eventID, "Event not existed");
            require(
                block.timestamp - thisEvent.timestamp < eventDuration,
                "Event already expired"
            );
            require(!provider.sent, "Already sent feedback.");
            provider.sent = true;
            provider.msgFeedback = msgTrust;
            provider.locFeedback = locTrust;

            uint40 providerWeight = provider.weight;

            // calcuate current honesty and feedback weight 
            uint40 voteLifeTimeCheck = 500; // @param change vote check limit as appropriate
            Node storage providerNode = nodes[MsgSender];
            
            uint256 currentTime = block.timestamp;
            uint256 votesLength = providerNode.votesLength;
            mapping(uint256 => Vote) storage voteList = thisNode.votes;

            // add default honesty score with 0.5 (scale of 1 to 100) score and weight of 100 (10000)
            uint40 totalHonesty = 5000;  // @param change as appropriate to default honesty
            uint40 totalHonestyWeight = 10000;  // @param change as appropriate to default honesty
            for (uint256 p = votesLength; p != 0;) {
                Vote storage thisVote = voteList[p - 1];
                uint256 timeDifference = currentTime - thisVote.timestamp; // difference in seconds
                uint256 dayDifference = timeDifference / 86400; // difference in days
                if (dayDifference > 68) {
                    // @param change event time limit as appropriate, should depend on decay factor
                    break; // stop loop and discard all events onwards that are far too old;
                }
                
                // exponential time decay smooth honesty 
                totalHonesty += (timeDecayList[dayDifference] * thisVote.honesty) / 100;
                totalHonestyWeight += (timeDecayList[dayDifference] * thisVote.honestyWeight) / 100;

                --voteLifeTimeCheck; // only count vote within feedback lifetime check
                if (voteLifeTimeCheck == 0) {
                    break; // discard all previous vote that exceed vote limit;
                }
                --p;
            }

            // providerWeight = providerWeight * totalHonesty / totalHonestyWeight;
            if (msgTrust) {
                thisEvent.msgTrustGoodWeight += providerWeight;
            } else {
                thisEvent.msgTrustBadWeight += providerWeight;
            }
            if (locTrust) {
                thisEvent.locTrustGoodWeight += providerWeight;
            } else {
                thisEvent.locTrustBadWeight += providerWeight;
            }
            thisEvent.feedbackCount += 1;
            thisEvent.providerAdrIndex[thisEvent.feedbackCount] = MsgSender;
            
            // Create new vote
            providerNode.votesIDIndex[thisEvent.eventID] = votesLength;
            providerNode.votes[votesLength].timestamp = thisEvent.timestamp;
            providerNode.votesLength += 1;
        }
    }

    /*
     * @dev Get trust value inputs for message and location from all events within limit
     * @dev The two values can then be used for Fuzzy function in Repcal contact
     */

    function feedbackAggregation(address nodeAddress)
    internal
    returns (uint40 msgNumerator, uint40 locNumerator)
    {
        unchecked {
            uint256 currentTime = block.timestamp;

        // add default reputation score at the end with 0.5 score and weight of 100 (10000)
            msgNumerator = 5000; // @param change as appropriate to default rep
            locNumerator = 5000; // @param change as appropriate to default rep
            uint40 msgDenominator = 10000; // @param change as appropriate to default rep
            uint40 locDenominator = 10000; // @param change as appropriate to default rep

            Node storage thisNode = nodes[nodeAddress];
            mapping(uint256 => Event) storage eventList = thisNode.events;
            uint256 eventsLength = thisNode.eventsLength;
            uint40 eventLifeTimeCheck = 500; // @param change event check limit as appropriate
            uint40 totalPenalty = 10000;
            for (uint256 p = eventsLength; p != 0;) {
                Event storage thisEvent = eventList[p - 1];
                uint256 timeDifference = currentTime - thisEvent.timestamp; // difference in seconds
                uint256 dayDifference = timeDifference / 86400; // difference in days
                if (dayDifference > 68) {
                    // @param change event time limit as appropriate, should depend on decay factor
                    break; // stop loop and discard all events onwards that are far too old;
                }
                if (thisEvent.finish == 0 && timeDifference < eventDuration) {
                    if (thisEvent.feedbackCount > 0) {
                        if (
                            thisEvent.msgTrustGoodWeight >
                            thisEvent.msgTrustBadWeight
                        ) {
                            // majority good msg vote

                            thisEvent.msgTrustWeight =
                                thisEvent.msgTrustGoodWeight *
                                thisEvent.criticalFactor;
                            thisEvent.msgTrustResult = true;
                        } else {
                            // majority bad msg vote
                            thisEvent.msgTrustWeight =
                                thisEvent.msgTrustBadWeight *
                                thisEvent.criticalFactor;
                            // add confidence penalty factor
                            thisEvent.penalty +=
                                (penaltyRate *
                                    (thisEvent.msgTrustBadWeight -
                                        thisEvent.msgTrustGoodWeight)) /
                                thisEvent.msgTrustBadWeight;
                        }
                        if (
                            thisEvent.locTrustGoodWeight >
                            thisEvent.locTrustBadWeight
                        ) {
                            // majority good loc vote
                            thisEvent.locTrustWeight =
                                thisEvent.locTrustGoodWeight *
                                thisEvent.criticalFactor;
                            thisEvent.locTrustResult = true;
                        } else {
                            // majority bad loc vote
                            thisEvent.locTrustWeight =
                                thisEvent.locTrustBadWeight *
                                thisEvent.criticalFactor;
                            // add confidence penalty factor
                            thisEvent.penalty +=
                                (penaltyRate *
                                    (thisEvent.locTrustBadWeight -
                                        thisEvent.locTrustGoodWeight)) /
                                thisEvent.locTrustBadWeight;
                        }
                        // recalculate each vote honesty based on result
                        uint256 feedbackCount = thisEvent.feedbackCount;
                        bool msgResult = thisEvent.msgTrustResult;
                        bool locResult = thisEvent.locTrustResult;
                        for (uint256 fc = feedbackCount; fc != 0;) {
                            address thisProviderAddress = thisEvent.providerAdrIndex[fc];
                            EventFeedbackProvider storage provider = thisEvent.providers[thisProviderAddress];
                            Node storage providerNode = nodes[thisProviderAddress];
                            if (provider.msgFeedback == msgResult){
                                uint256 voteIndex = providerNode.votesIDIndex[thisEvent.eventID];
                                providerNode.votes[voteIndex].honesty += 50 * thisEvent.locTrustWeight;
                            }
                            
                            if (provider.locFeedback == locResult){

                            }
                            // if (msgResult == )
                            --p;
                        }

                        thisEvent.finish = 1; // closed event
                    } else {
                        thisEvent.finish = 2; // event has no feedback
                    }
                }

                if (thisEvent.finish == 1) {
                    // event has feedback and finish closing
                    // exponential time decay smooth trust and weight

                    totalPenalty += thisEvent.penalty;
                    if (!thisEvent.msgTrustResult) {
                        // bad msg trust
                        msgDenominator +=
                            (timeDecayList[dayDifference] *
                            thisEvent.msgTrustWeight *
                                totalPenalty) /
                            1000000;
                    } else {
                        // good msg trust
                        uint40 msgWeight = (timeDecayList[dayDifference] *
                            thisEvent.msgTrustWeight) / 100;
                        msgDenominator += msgWeight;
                        msgNumerator += msgWeight;
                    }
                    if (!thisEvent.locTrustResult) {
                        // bad msg trust
                        locDenominator +=
                            (timeDecayList[dayDifference] *
                            thisEvent.locTrustWeight *
                                totalPenalty) /
                            1000000;
                    } else {
                        // good msg trust
                        uint40 locWeight = (timeDecayList[dayDifference] *
                            thisEvent.locTrustWeight) / 100;
                        locDenominator += locWeight;
                        locNumerator += locWeight;
                    }

                    --eventLifeTimeCheck; // only count event with feedback for lifetime check
                    if (eventLifeTimeCheck == 0) {
                        break; // discard all previous events that exceed event limit;
                    }
                }
                --p;
            }
            // find weighted average and convert value to fuzzy function scale where 1 = 1000
            if (msgDenominator != 0) {
                // handle denominator 0
                msgNumerator = (msgNumerator * 1000) / msgDenominator;
            } else {
                msgNumerator = 0;
            }
            if (locNumerator != 0) {
                // handle denominator 0
                locNumerator = (locNumerator * 1000) / locDenominator;
            } else {
                locNumerator = 0;
            }
        }
    }

    function valueAtUnionOfTerms(CorrectedTerm[9] memory union, uint40 x)
    internal
    pure
    returns (
        uint40 max // max value from all Terms
    )
    {
        unchecked {
            for (uint8 p; p < 9;) {
                CorrectedTerm memory term = union[p];
                uint40 check;
                uint40 belief = term.beliefDegree;

                if (belief != 0) {
                    check = valueAtTerm(term.mfParams, x);
                }
                if (belief <= check) {
                    check = belief;
                }
                if (check > max) {
                    max = check;
                }
                ++p;
            }
        }
    }

    function valueAtTerm(uint40[4] memory mfParams, uint40 x)
    internal
    pure
    returns (uint40)
    {
        /**
         * Trapezoidal membership function.
         * @param {number} x
         * @param {number} 0 left f(left) = 0
         * @param {number} 1 maxLeft f(maxLeft) = 1
         * @param {number} 2 maxRight f(maxRight) = 1
         * @param {number} 3 right f(right) = 0
         * @returns {number}
         */
        unchecked {
            uint40 mfParams0 = mfParams[0];
            uint40 mfParams1 = mfParams[1];
            uint40 mfParams2 = mfParams[2];
            uint40 mfParams3 = mfParams[3];
            if (x < mfParams0 || x > mfParams3) {
                return 0;
            } else if (mfParams0 <= x && x <= mfParams1) {
                return ((x - mfParams0) * 1000) / (mfParams1 - mfParams0);
            } else if (mfParams1 <= x && x <= mfParams2) {
                return 1000;
            }
            return ((mfParams3 - x) * 1000) / (mfParams3 - mfParams2);
        }
    }

    /*
     * @dev Calculate reputation score with fuzzy logic
     * @param message and location trust score
     */
    function currentReputation(uint40 inputValue1, uint40 inputValue2)
    internal
    view
    returns (uint40 result)
    {
        unchecked {
            CorrectedTerm[9] memory union;
            for (uint8 i; i < 9;) {
                // for each Rule get values at the right parts
                uint40 min = 1000;
                Rule memory thisRule = fuzzyRules[i];
                uint40 checkValue = valueAtTerm(
                    fuzzyInput.terms[thisRule.conditions[0]].mfParams,
                    inputValue1
                );
                if (checkValue < min) {
                    min = checkValue;
                }
                checkValue = valueAtTerm(
                    fuzzyInput.terms[thisRule.conditions[1]].mfParams,
                    inputValue2
                );
                if (checkValue < min) {
                    min = checkValue;
                }
                union[i] = CorrectedTerm(
                    fuzzyOutput.terms[thisRule.conclusion].mfParams,
                    min
                );
                ++i;
            }

        // Get mass center
            uint40 s;
            while (result < 1000) {
                result += 10;
                s += (10 * valueAtUnionOfTerms(union, result));
            }
            result = 0;
            uint40 newS;
            s = s >> 1; // divide by 2
            while (newS < s) {
                result += 10;
                newS += (10 * valueAtUnionOfTerms(union, result));
            }
        // now it equals to 'mass center'. In prev point S < S/2, in next point  S > S/2
        }
    }

    /*
     * @dev Give feedback (including weight delegated to provider) to event.
     * @param choice index of choice in the choices array
     */
    function checkEvent(address eventOwnerAddress, uint256 eventIndex)
    external
    view
    returns (
        uint256 eventID,
        uint40 eventType,
        uint256 timestamp,
        bool msgTrustResult,
        bool locTrustResult,
        uint40 msgTrustWeight,
        uint40 locTrustWeight,
        int256[2] memory coordinate,
        address rsuAddress,
        uint8 finish,
        uint256 voteTimeRemain
    )
    {
        Event storage thisEvent = nodes[eventOwnerAddress].events[eventIndex];
        eventID = thisEvent.eventID;
        eventType = thisEvent.eventType;
        timestamp = thisEvent.timestamp;
        msgTrustResult = thisEvent.msgTrustResult;
        locTrustResult = thisEvent.locTrustResult;
        msgTrustWeight = thisEvent.msgTrustWeight;
        locTrustWeight = thisEvent.locTrustWeight;
        coordinate = thisEvent.coordinate;
        rsuAddress = thisEvent.rsuAddress;
        finish = thisEvent.finish;
        voteTimeRemain = block.timestamp - thisEvent.timestamp;
    }

    /*
     * @dev Submit owner function transaction for confirmation.
     * @param function intended to be called from the transaction
     * @param address list for function input
     */
    function submitOwnerTransaction(
        uint40 functionID,
        address[] memory addressList
    ) external onlySmartContractOwner {
        require(functionID < 8, "functionID not exist");
        require(addressList.length != 0, "require address input");
        ownerFunctionTransaction storage thisTX = ownerTransactions[
                    ownerTransactionCount
            ];
        thisTX.functionID = functionID;
        thisTX.sender = msg.sender;
        thisTX.addressList = addressList;
        confirmOwnerTransaction(ownerTransactionCount);
        ++ownerTransactionCount;
    }

    function confirmOwnerTransaction(uint256 transactionId)
    public
    onlySmartContractOwner
    {
        ownerFunctionTransaction storage thisTX = ownerTransactions[
                    transactionId
            ];
        require(!thisTX.executed, "TX already executed");
        require(thisTX.addressList.length != 0, "Event not exist");
        require(!thisTX.confirmList[msg.sender], "You already confirmed");
        thisTX.confirmList[msg.sender] = true;
        ++thisTX.confirmations;
        if (thisTX.confirmations >= requiredOwnersConfirmation) {
            executeTransaction(transactionId);
        }
    }

    function deleteOwnerTransaction(uint256 txIndex)
    external
    onlySmartContractOwner
    {
        ownerFunctionTransaction storage thisTX = ownerTransactions[txIndex];
        require(thisTX.addressList.length != 0, "TX not exist");
        require(thisTX.sender == msg.sender, "Original sender only");
        delete ownerTransactions[txIndex];
    }

    function executeTransaction(uint256 transactionId) internal {
        unchecked {
            ownerFunctionTransaction storage thisTX = ownerTransactions[
                        transactionId
                ];

            uint40 functionID = thisTX.functionID;
            if (functionID == 0) {
                // add owners
                addOwners(thisTX.addressList);
            } else if (functionID == 1) {
                // remove owners
                removeOwners(thisTX.addressList);
            } else if (functionID == 2) {
                // add nodes
                addNodes(thisTX.addressList, false, false);
            } else if (functionID == 3) {
                // add pretrust nodes
                addNodes(thisTX.addressList, true, false);
            } else if (functionID == 4) {
                // add rsu nodes
                addNodes(thisTX.addressList, false, true);
            } else if (functionID == 5) {
                // remove nodes
                removeNodes(thisTX.addressList, false);
            } else if (functionID == 6) {
                // remove rsu nodes
                removeNodes(thisTX.addressList, true);
            } else if (functionID == 7) {
                // change owner confirmation number
                changeConfirmationNumber(thisTX.addressList.length);
            }
            thisTX.executed = true;
        }
    }

    /*
     * @dev Add nodes to database.
     * @param address list of nodes
     * @param pretrust nodes classification
     * @param rsu nodes classification
     */
    function addNodes(
        address[] memory addressList,
        bool pretrust,
        bool rsu
    ) internal {
        for (uint256 p; p < addressList.length;) {
            unchecked {
                if (rsu) {
                    rsus[addressList[p]] = true;
                } else {
                    if (!nodes[addressList[p]].exist) {
                        // Already existed nodes will not be added again
                        nodes[addressList[p]].preTrust = pretrust;
                        nodes[addressList[p]].currentReputation = 500; // @param change default rep value as appropriate
                        nodes[addressList[p]].currentHonesty = 500; // @param change default honesty value as appropriate
                        nodes[addressList[p]].exist = true;
                    }
                }
                ++p;
            }
        }
    }

    /*
     * @dev Remove nodes from database.
     * @param address list of nodes
     */
    function removeNodes(address[] memory addressList, bool rsu) internal {
        for (uint256 p; p < addressList.length;) {
            if (rsu) {
                delete rsus[addressList[p]];
            } else {
                delete nodes[addressList[p]];
            }
            unchecked {
                ++p;
            }
        }
    }

    /*
     * @dev Change confirmation requirement.
     * @param address list (address not used but length indicate new number)
     */
    function changeConfirmationNumber(uint256 newNumber) internal {
        require(newNumber != 0, "Cannot be 0");
        require(newNumber <= ownerCount, "Cannot > number of owners");
        requiredOwnersConfirmation = newNumber;
    }

    /*
     * @dev Add owners.
     * @param address list
     */
    function addOwners(address[] memory addressList) internal {
        for (uint256 p; p < addressList.length;) {
            unchecked {
                if (!owners[addressList[p]]) {
                    owners[addressList[p]] = true;
                    ownerCount += 1;
                }
                ++p;
            }
        }
    }

    /*
     * @dev Remove owners.
     * @param address list
     */
    function removeOwners(address[] memory addressList) internal {
        require(
            ownerCount - addressList.length >= requiredOwnersConfirmation,
            "Owners lower than requirement"
        );
        for (uint256 p; p < addressList.length;) {
            delete owners[addressList[p]];
            unchecked {
                ++p;
            }
        }
        unchecked {
            ownerCount -= addressList.length;
        }
    }
}
